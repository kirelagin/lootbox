{-# LANGUAGE RecordWildCards #-}

-- | Common ZMQ TCP types and functions.

module Loot.Network.ZMQ.Common
    ( ZmqTcp
    , ZTGlobalEnv(..)
    , ztContext
    , ztLog
    , withZTGlobalEnv
    , endpointTcp
    , ZTNodeId(..)
    , ztNodeIdRouter
    , ztNodeIdPub
    , ztNodeConnectionId
    , ztNodeConnectionIdUnsafe
    , heartbeatSubscription
    ) where


import Codec.Serialise (Serialise)
import Control.Lens (makeLenses)
import qualified Data.ByteString.Char8 as BS8

import qualified Data.Restricted as Z
import qualified System.ZMQ4 as Z

import Loot.Log (Level)
import Loot.Network.Class (Subscription (..))


-- | Networking tag type for ZMQ over TCP.
data ZmqTcp

-- | Global environment needed for client/server initialisation.
data ZTGlobalEnv = ZTGlobalEnv
    { _ztContext :: Z.Context
    , _ztLog     :: Level -> Text -> IO ()
    }

makeLenses ''ZTGlobalEnv

-- | Bracket for ZmqTcp global environment.
withZTGlobalEnv ::
       (MonadMask m, MonadIO m)
    => (Level -> Text -> IO ())
    -> (ZTGlobalEnv -> m a)
    -> m a
withZTGlobalEnv logFunc action =
    bracket (liftIO Z.context) (liftIO . Z.term) $
    \ctx -> action $ ZTGlobalEnv ctx logFunc

-- | Generic tcp address creation helper.
endpointTcp :: String -> Integer -> String
endpointTcp h p = "tcp://" <> h <> ":" <> show p

-- | NodeId as seen in ZMQ TCP.
data ZTNodeId = ZTNodeId
    { ztIdHost       :: String  -- ^ Host.
    , ztIdRouterPort :: Integer -- ^ Port for ROUTER socket.
    , ztIdPubPort    :: Integer -- ^ Port for PUB socket.
    } deriving (Eq, Ord, Show, Generic)

instance Serialise ZTNodeId

-- | Address of the server's ROUTER/frontend socket.
ztNodeIdRouter :: ZTNodeId -> String
ztNodeIdRouter ZTNodeId{..} = endpointTcp ztIdHost ztIdRouterPort

-- | Address of the server's PUB socket.
ztNodeIdPub :: ZTNodeId -> String
ztNodeIdPub ZTNodeId{..} = endpointTcp ztIdHost ztIdPubPort

-- TODO Make unsafe version of this function maybe.
-- | Agreed standard of server identities public nodes must set on
-- their ROUTER frontend. Identifiers are size limited -- this
-- function errors if it's not possible to create a valid id from the
-- given ZTNodeId. You can wrap it again using 'Z.restrict'.
ztNodeConnectionId :: ZTNodeId -> ByteString
ztNodeConnectionId zId = -- ZTNodeId{..} =
    let sid = ztNodeConnectionIdUnsafe zId
    in Z.rvalue $
       fromMaybe (error $ "ztNodeConnectionId: restriction check failed " <> show sid) $
       (Z.toRestricted sid :: Maybe (Z.Restricted (Z.N1, Z.N254) ByteString))

-- | Unsafe variant of 'ztNodeConnectionId' which doesn't check
-- whether string is empty or too long.
ztNodeConnectionIdUnsafe :: ZTNodeId -> ByteString
ztNodeConnectionIdUnsafe ZTNodeId{..} =
    -- Yes, we use host:frontendPort, it doesn't seem to have
    -- any downsides.
    BS8.pack $ endpointTcp ztIdHost ztIdRouterPort

-- | Key for heartbeat subscription.
heartbeatSubscription :: Subscription
heartbeatSubscription = Subscription "_hb"