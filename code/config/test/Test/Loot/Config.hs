{- This Source Code Form is subject to the terms of the Mozilla Public
 - License, v. 2.0. If a copy of the MPL was not distributed with this
 - file, You can obtain one at http://mozilla.org/MPL/2.0/.
 -}

{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE TypeFamilies     #-}
{-# LANGUAGE TypeOperators    #-}

module Test.Loot.Config where

import Data.Aeson (FromJSON, eitherDecode)
import Loot.Base.HasLens (lensOf)
import Options.Applicative (Parser, auto, defaultPrefs, execParserPure, getParseResult, info, long)
import qualified Options.Applicative as O

import Loot.Config

import Hedgehog (Property, forAll, property, (===))
import Test.Tasty.HUnit (Assertion, assertEqual, assertFailure, (@=?))

import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range

newtype SomeKek = SomeKek Integer deriving (Eq,Ord,Show,Read,Generic,FromJSON)
newtype SomeMem = SomeMem String deriving (Eq,Ord,Show,IsString,Generic,FromJSON)

type Fields = '[ "str" ::: String
               , "int" ::: Int
               , "sub" ::< SubFields
               , "kek" ::: SomeKek
               ]

type SubFields = '[ "int2" ::: Int
                  , "bool" ::: Bool
                  , "sub2" ::< Sub2Fields
                  ]

type Sub2Fields = '[ "str2" ::: String
                   , "mem"  ::: SomeMem
                   ]

cfg :: PartialConfig Fields
cfg = mempty


unit_emptyPartial :: Assertion
unit_emptyPartial = do
    let s :: Text
        s = "{str <unset>, int <unset>, sub =< {int2 <unset>, bool <unset>, sub2 =< {str2 <unset>, mem <unset>}}, kek <unset>}"
    s @=? show cfg


unit_lensesEmptyPartial :: Assertion
unit_lensesEmptyPartial = do
    cfg ^. option #str @=? Nothing
    cfg ^. option #int @=? Nothing
    cfg ^. sub #sub @=? (mempty :: PartialConfig SubFields)

    cfg ^. sub #sub . option #int2 @=? Nothing
    cfg ^. sub #sub . option #bool @=? Nothing
    cfg ^. sub #sub . sub #sub2 @=? (mempty :: PartialConfig Sub2Fields)

    cfg ^. sub #sub . sub #sub2 . option #str2 @=? Nothing

hprop_lensOptionPartial :: Property
hprop_lensOptionPartial = property $ do
    str <- forAll $ Gen.string (Range.linear 0 10) Gen.enumBounded
    let cfg1 = cfg & option #str ?~ str
    cfg1 ^. option #str === Just str

    int <- forAll $ Gen.int Range.constantBounded
    let cfg2 = cfg1 & option #int ?~ int
    cfg2 ^. option #str === Just str
    cfg2 ^. option #int === Just int

    let cfg3 = cfg1 & option #int .~ Nothing
    cfg3 ^. option #str === Just str
    cfg3 ^. option #int === Nothing

hprop_lensSubOptionPartial :: Property
hprop_lensSubOptionPartial = property $ do
    int <- forAll $ Gen.int Range.constantBounded
    let cfg1 = cfg & sub #sub . option #int2 ?~ int
    cfg1 ^. sub #sub . option #int2 === Just int

    str <- forAll $ Gen.string (Range.linear 0 10) Gen.enumBounded
    let cfg2 = cfg1 & sub #sub . sub #sub2 . option #str2 ?~ str
    cfg2 ^. sub #sub . option #int2 === Just int
    cfg2 ^. sub #sub . sub #sub2 . option #str2 === Just str


hprop_mappendPartial :: Property
hprop_mappendPartial = property $ do
    str1 <- forAll $ Gen.string (Range.linear 0 10) Gen.enumBounded
    let cfg1 = cfg & option #str ?~ str1

    let cfg01 = cfg <> cfg1
    cfg01 ^. option #str === Just str1
    cfg01 ^. option #int === Nothing

    str2 <- forAll $ Gen.string (Range.linear 0 10) Gen.enumBounded
    int <- forAll $ Gen.int Range.constantBounded
    let cfg2 = cfg & option #str ?~ str2
                   & option #int ?~ int

    let cfg02 = cfg <> cfg2
    cfg02 ^. option #str === Just str2
    cfg02 ^. option #int === Just int

    let cfg12 = cfg1 <> cfg2
    cfg12 === cfg02

    str3 <- forAll $ Gen.string (Range.linear 0 10) Gen.enumBounded
    let cfg3 = cfg & sub #sub . sub #sub2 . option #str2 ?~ str3

    let cfg123 = cfg1 <> cfg2 <> cfg3
    cfg123 ^. option #str === Just str2
    cfg123 ^. option #int === Just int
    cfg123 ^. sub #sub . sub #sub2 . option #str2 === Just str3


-- | Helper for testing JSON decoding.
testDecode :: String -> PartialConfig Fields -> Assertion
testDecode str expected = Right expected @=? eitherDecode (fromString str)

unit_parseJsonEmpty :: Assertion
unit_parseJsonEmpty = testDecode "{}" cfg

unit_parseJson1 :: Assertion
unit_parseJson1 =
    testDecode "{ \"str\": \"hi\" }" $
        cfg & option #str ?~ "hi"

unit_parseJson2 :: Assertion
unit_parseJson2 =
    testDecode "{ \"str\": \"hi\", \"int\": 4 }" $
        cfg & option #str ?~ "hi"
            & option #int ?~ 4

unit_parseJsonSubEmpty :: Assertion
unit_parseJsonSubEmpty =
    testDecode "{ \"str\": \"hi\", \"sub\": {} }" $
        cfg & option #str ?~ "hi"

unit_parseJsonSub :: Assertion
unit_parseJsonSub =
    testDecode "{ \"str\": \"hi\", \"sub\": { \"bool\": true } }" $
        cfg & option #str ?~ "hi"
            & sub #sub . option #bool ?~ True

unit_parseJsonSubSub :: Assertion
unit_parseJsonSubSub =
    testDecode "{ \"sub\": { \"sub2\": { \"str2\": \"hi\" } } }" $
        cfg & sub #sub . sub #sub2 . option #str2 ?~ "hi"


-----------------------
-- Finalisation
-----------------------

unit_finaliseEmpty :: Assertion
unit_finaliseEmpty =
    Left missing @=? finalise cfg
  where
    missing =
        [ "str", "int"
        , "sub.int2", "sub.bool"
        , "sub.sub2.str2"
        , "sub.sub2.mem"
        , "kek"
        ]

unit_finaliseSome :: Assertion
unit_finaliseSome = do
    let cfg1 = cfg & option #str ?~ "hi"
                   & sub #sub . option #bool ?~ False
                   & sub #sub . sub #sub2 . option #str2 ?~ ""
                   & option #kek ?~ (SomeKek 1)
    Left missing @=? finalise cfg1
  where
    missing =
        [ "int"
        , "sub.int2"
        , "sub.sub2.mem"
        ]

fullConfig :: ConfigRec 'Partial Fields
fullConfig =
    cfg & option #str ?~ "hey"
        & option #int ?~ 12345
        & option #kek ?~ (SomeKek 999)
        & sub #sub . option #bool ?~ False
        & sub #sub . option #int2 ?~ 13579
        & sub #sub . sub #sub2 . option #str2 ?~ ""
        & sub #sub . sub #sub2 . option #mem ?~ (SomeMem "bye")

unit_finalise :: Assertion
unit_finalise = do
    let cfg1 = fullConfig
    let efinalCfg = finalise cfg1

    case efinalCfg of
        Left _ -> assertFailure "Valid config was not finalised properly"
        Right finalCfg -> do
            "hey"           @=? finalCfg ^. option #str
            12345           @=? finalCfg ^. option #int
            (SomeKek 999)   @=? finalCfg ^. option #kek
            False           @=? finalCfg ^. sub #sub . option #bool
            13579           @=? finalCfg ^. sub #sub . option #int2
            ""              @=? finalCfg ^. sub #sub . sub #sub2 . option #str2
            (SomeMem "bye") @=? finalCfg ^. sub #sub . sub #sub2 . option #mem

            finalCfg ^. (lensOf @SomeKek) @=? (SomeKek 999)
            finalCfg ^. (lensOf @SomeMem) @=? (SomeMem "bye")
            finalCfg ^. (lensOfC @('["kek"])) @=? (SomeKek 999)
            finalCfg ^. (lensOfC @('["sub", "sub2", "mem"])) @=? (SomeMem "bye")

----------------------
-- CLI modifications
----------------------

runCliArgs :: Parser a -> [String] -> Maybe a
runCliArgs p = getParseResult . execParserPure defaultPrefs (info p mempty)

fieldsParser :: OptModParser Fields
fieldsParser =
    #str .:: (O.strOption $ long "str") <*<
    #int .:: (O.option auto $ long "int") <*<
    #sub .:<
        (#int2 .:: (O.option auto $ long "int2") <*<
         #bool .:: (O.flag' True $ long "bool") <*<
         #sub2 .:<
              (#str2 .:: (O.strOption $ long "str2") <*<
               #mem .:: (O.strOption $ long "mem"))
        ) <*<
    #kek .:: (O.option auto $ long "kek")

unit_cliOverrideEmptyId :: Assertion
unit_cliOverrideEmptyId = do
    noMod <- maybe (assertFailure "Config parser fails on empty arguments") pure $
             runCliArgs fieldsParser []
    noMod cfg @=? cfg
    noMod fullConfig @=? fullConfig

someArgs :: [String]
someArgs =
    [ "--int", "228"
    , "--mem", "hi"
    , "--bool"
    , "--kek", "SomeKek 777"
    ]

unit_cliOverrideSetNew :: Assertion
unit_cliOverrideSetNew = do
    someMod <- maybe (assertFailure "Config parser failed") pure $
               runCliArgs fieldsParser someArgs
    let cfg1 = someMod cfg
    assertEqual "CLI parser modifies empty config incorrectly" cfg1 $
        cfg & option #int ?~ 228
            & sub #sub . option #bool ?~ True
            & sub #sub . sub #sub2 . option #mem ?~ (SomeMem "hi")
            & option #kek ?~ (SomeKek 777)

unit_cliOverrideModExisting :: Assertion
unit_cliOverrideModExisting = do
    someMod <- maybe (assertFailure "Config parser failed") pure $
               runCliArgs fieldsParser someArgs
    let cfg1 = someMod fullConfig
    assertEqual "CLI parser modifies non-empty config incorrectly" cfg1 $
        fullConfig & option #int ?~ 228
                   & sub #sub . option #bool ?~ True
                   & sub #sub . sub #sub2 . option #mem ?~ (SomeMem "hi")
                   & option #kek ?~ (SomeKek 777)
