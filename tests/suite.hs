import Test.Framework (defaultMain, testGroup, Test)
import Test.Framework.Providers.HUnit
import Test.Framework.Providers.QuickCheck2
import Test.QuickCheck
import Test.HUnit hiding (Test)

import Data.List (find)
import Crypto.Random
import Data.Binary
import qualified Data.OpenPGP as OpenPGP
import qualified Data.OpenPGP.CryptoAPI as OpenPGP
import qualified Data.ByteString.Lazy as LZ
import qualified Data.ByteString.Lazy.UTF8 as LZ (fromString, toString)

instance Arbitrary OpenPGP.HashAlgorithm where
	arbitrary = elements [OpenPGP.MD5, OpenPGP.SHA1, OpenPGP.RIPEMD160, OpenPGP.SHA256, OpenPGP.SHA384, OpenPGP.SHA512, OpenPGP.SHA224]

instance Arbitrary OpenPGP.SymmetricAlgorithm where
	arbitrary = elements [OpenPGP.AES128, OpenPGP.AES192, OpenPGP.AES256, OpenPGP.Blowfish]

testFingerprint :: FilePath -> String -> Assertion
testFingerprint fp kf = do
	bs <- LZ.readFile $ "tests/data/" ++ fp
	let (OpenPGP.Message [packet]) = decode bs
	assertEqual ("for " ++ fp) kf (OpenPGP.fingerprint packet)

testVerifyMessage :: FilePath -> FilePath -> Assertion
testVerifyMessage keyring message = do
	keys <- fmap decode $ LZ.readFile $ "tests/data/" ++ keyring
	m <- fmap decode $ LZ.readFile $ "tests/data/" ++ message
	let verification = OpenPGP.verify keys m 0
	assertEqual (keyring ++ " for " ++ message) True verification

testDecryptHello :: Assertion
testDecryptHello = do
	keys <- fmap decode $ LZ.readFile $ "tests/data/helloKey.gpg"
	m <- fmap decode $ LZ.readFile $ "tests/data/hello.gpg"
	let Just (OpenPGP.Message [OpenPGP.CompressedDataPacket {
			OpenPGP.message = OpenPGP.Message msg
		}]) = OpenPGP.decrypt keys m
	let content = fmap (LZ.toString . OpenPGP.content) (find isLiteral msg)
	assertEqual "Decrypt hello" (Just "hello\n") content
	where
	isLiteral (OpenPGP.LiteralDataPacket {}) = True
	isLiteral                              _ = False

prop_sign_and_verify :: (CryptoRandomGen g) => OpenPGP.Message -> g -> OpenPGP.HashAlgorithm -> String -> String -> Gen Bool
prop_sign_and_verify secring g halgo filename msg = do
	keyid <- elements ["FEF8AFA0F661C3EE","7F69FA376B020509"]
	let m = OpenPGP.LiteralDataPacket {
			OpenPGP.format = 'u',
			OpenPGP.filename = filename,
			OpenPGP.timestamp = 12341234,
			OpenPGP.content = LZ.fromString msg
		}
	let sig = OpenPGP.sign secring (OpenPGP.Message [m])
			halgo keyid 12341234 g
	return $ OpenPGP.verify secring (OpenPGP.Message [sig,m]) 0

prop_encrypt_and_decrypt :: (CryptoRandomGen g) => OpenPGP.Message -> g -> OpenPGP.SymmetricAlgorithm -> String -> String -> Bool
prop_encrypt_and_decrypt secring g algo filename msg =
	case OpenPGP.encrypt secring algo m g of
		Left _ -> False
		Right (encM, _) -> OpenPGP.decrypt secring encM == Just m
	where
	m = OpenPGP.Message [OpenPGP.LiteralDataPacket {
			OpenPGP.format = 'u',
			OpenPGP.filename = filename,
			OpenPGP.timestamp = 12341234,
			OpenPGP.content = LZ.fromString msg
		}]

tests :: (CryptoRandomGen g) => OpenPGP.Message -> OpenPGP.Message -> g -> [Test]
tests secring oneKey rng =
	[
		testGroup "Fingerprint" [
			testCase "000001-006.public_key" (testFingerprint "000001-006.public_key" "421F28FEAAD222F856C8FFD5D4D54EA16F87040E"),
			testCase "000016-006.public_key" (testFingerprint "000016-006.public_key" "AF95E4D7BAC521EE9740BED75E9F1523413262DC"),
			testCase "000027-006.public_key" (testFingerprint "000027-006.public_key" "1EB20B2F5A5CC3BEAFD6E5CB7732CF988A63EA86"),
			testCase "000035-006.public_key" (testFingerprint "000035-006.public_key" "CB7933459F59C70DF1C3FBEEDEDC3ECF689AF56D")
		],
		testGroup "Message verification" [
			testCase "uncompressed-ops-dsa" (testVerifyMessage "pubring.gpg" "uncompressed-ops-dsa.gpg"),
			testCase "uncompressed-ops-dsa-sha384" (testVerifyMessage "pubring.gpg" "uncompressed-ops-dsa-sha384.txt.gpg"),
			testCase "uncompressed-ops-rsa" (testVerifyMessage "pubring.gpg" "uncompressed-ops-rsa.gpg"),
			testCase "compressedsig" (testVerifyMessage "pubring.gpg" "compressedsig.gpg"),
			testCase "compressedsig-zlib" (testVerifyMessage "pubring.gpg" "compressedsig-zlib.gpg"),
			testCase "compressedsig-bzip2" (testVerifyMessage "pubring.gpg" "compressedsig-bzip2.gpg")
		],
		testGroup "Signing" [
			testProperty "Crypto signatures verify" (prop_sign_and_verify secring rng)
		],
		testGroup "Decryption" [
			testCase "decrypt hello" testDecryptHello
		],
		testGroup "Encryption" [
			testProperty "Encrypted messages decrypt" (prop_encrypt_and_decrypt oneKey rng)
		]
	]

main :: IO ()
main = do
	rng <- newGenIO :: IO SystemRandom
	secring <- fmap decode $ LZ.readFile "tests/data/secring.gpg"
	oneKey <- fmap decode $ LZ.readFile "tests/data/helloKey.gpg"
	defaultMain (tests secring oneKey rng)
