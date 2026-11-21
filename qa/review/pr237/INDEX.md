# Presets v2 review patches

Each patch is under 6 KB. `git blob` is `git hash-object` of the source, which matches the blob in the freeze commit.

| Patch | Source | Lines | Bytes | sha256 | git blob |
| --- | --- | --- | --- | --- | --- |
| `01-VoiceQualityMeter-part1.patch` | `Sources/ZeusCore/Providers/VoiceQualityMeter.swift` | 1-133 | 6095 | `8bdaf2033848290659388a94d436df3c679f10868c10d9c132731e17cc8a714d` | `4087c8037f000928cec28a7f7031bbdcc587d395` |
| `02-VoiceQualityMeter-part2.patch` | `Sources/ZeusCore/Providers/VoiceQualityMeter.swift` | 134-148 | 833 | `4263e1e7f42f4bcfa033ba6113add5748f6a3d23984c89d9296c1d92ad673d86` | `4087c8037f000928cec28a7f7031bbdcc587d395` |
| `03-VoiceQualityPreset-part1.patch` | `Sources/ZeusCore/Providers/VoiceQualityPreset.swift` | 1-129 | 6093 | `e21e3b83db574dd10454ec2e5ce6358cd765500ee9f9216c5e925908b6c46eae` | `52f3b6a725d981a1eb945464b993554c01c7c2c8` |
| `04-VoiceQualityPreset-part2.patch` | `Sources/ZeusCore/Providers/VoiceQualityPreset.swift` | 130-267 | 6061 | `fb6a30f30a15a63ff7c760aaf97bf0f36b664dd93a547e0abb4f70fb94a39e7a` | `52f3b6a725d981a1eb945464b993554c01c7c2c8` |
| `05-VoiceQualityPreset-part3.patch` | `Sources/ZeusCore/Providers/VoiceQualityPreset.swift` | 268-398 | 6074 | `2b6be919925141fac533838d906c784d9b6bc33cde69a13b14755361a097bd3d` | `52f3b6a725d981a1eb945464b993554c01c7c2c8` |
| `06-VoiceQualityPreset-part4.patch` | `Sources/ZeusCore/Providers/VoiceQualityPreset.swift` | 399-526 | 6129 | `4232a091c77aa2cd323d5bd48c2a7aadda9df12b897e370ab1e73f5619de131e` | `52f3b6a725d981a1eb945464b993554c01c7c2c8` |
| `07-VoiceQualityPreset-part5.patch` | `Sources/ZeusCore/Providers/VoiceQualityPreset.swift` | 527-634 | 6063 | `0b8b967e4198332e9e5d1ab5b79d0da23c8999400239ccfc77daabd7b3797537` | `52f3b6a725d981a1eb945464b993554c01c7c2c8` |
| `08-VoiceQualityPreset-part6.patch` | `Sources/ZeusCore/Providers/VoiceQualityPreset.swift` | 635-713 | 3894 | `d4f2a5b074b62431dd272719fa1004718aa61e8e491ef9964dcff6763c95c088` | `52f3b6a725d981a1eb945464b993554c01c7c2c8` |
| `09-ProviderTypes-part1.patch` | `Sources/ZeusCore/Providers/ProviderTypes.swift` | 1-158 | 6123 | `97a64f7712e1a0b86b66c7eb78d0a354b03f40ee999b9a72d212ac6612af3564` | `c03e46c7a22f607a3df10067f208f5642a024b25` |
| `10-ProviderTypes-part2.patch` | `Sources/ZeusCore/Providers/ProviderTypes.swift` | 159-234 | 3838 | `e200bf007b5fcb6ecbcf97874debf534e00ec45125ee0d8e5dc3662743a40120` | `c03e46c7a22f607a3df10067f208f5642a024b25` |
| `11-CredentialStore-part1.patch` | `Sources/ZeusCore/Providers/CredentialStore.swift` | 1-109 | 4674 | `93c56c8805eca10d6445c5260b7c7f9e92b4e95320685fb4edccd7b8722e3c68` | `f0793dfc982cdd60b72ca5de593dc926e2c14455` |
| `12-VoiceQualityPresetTests-part1.patch` | `Tests/ZeusCoreTests/VoiceQualityPresetTests.swift` | 1-114 | 6143 | `894cdf1c256fd6aeeb15db1761545a273a3ae9938aa9f1c4d41224ae41d5a14d` | `6198b12f920b0a27f5f32e9b549d5bd3ac159004` |
| `13-VoiceQualityPresetTests-part2.patch` | `Tests/ZeusCoreTests/VoiceQualityPresetTests.swift` | 115-224 | 6100 | `0454169b2180e2da408d60c0495559f5f3b99ffa50c59180dc46753a6d230df0` | `6198b12f920b0a27f5f32e9b549d5bd3ac159004` |
| `14-VoiceQualityPresetTests-part3.patch` | `Tests/ZeusCoreTests/VoiceQualityPresetTests.swift` | 225-328 | 6126 | `c112bd57d3048ee6600e66ff0c71d3e0601f1ad0e810bdac4d647c5e00fce2d8` | `6198b12f920b0a27f5f32e9b549d5bd3ac159004` |
| `15-VoiceQualityPresetTests-part4.patch` | `Tests/ZeusCoreTests/VoiceQualityPresetTests.swift` | 329-460 | 6138 | `76bf6e104b1d0857bd7f755c96297673d6b386c29134cb4c95117c0cf667ce09` | `6198b12f920b0a27f5f32e9b549d5bd3ac159004` |
| `16-VoiceQualityPresetTests-part5.patch` | `Tests/ZeusCoreTests/VoiceQualityPresetTests.swift` | 461-562 | 4048 | `fdcaaef87bcdcf2030d3c9f6d8dfb81a276af029673dee629eea984cf268850b` | `6198b12f920b0a27f5f32e9b549d5bd3ac159004` |
| `17-VoiceQualityRouteSecurityTests-part1.patch` | `Tests/ZeusCoreTests/VoiceQualityRouteSecurityTests.swift` | 1-97 | 6127 | `83f8dd914fc5c95290c171d064cfb9316d76f94d5efcd0ff96db4b450ad59a3e` | `42701ce54d290aa6f9d68cfe25dc3e80aaa40437` |
| `18-VoiceQualityRouteSecurityTests-part2.patch` | `Tests/ZeusCoreTests/VoiceQualityRouteSecurityTests.swift` | 98-208 | 6073 | `058e48618d4beae2a5d4f2db8d467ce4c607091063dc6d60039c73c996913e3e` | `42701ce54d290aa6f9d68cfe25dc3e80aaa40437` |
| `19-VoiceQualityRouteSecurityTests-part3.patch` | `Tests/ZeusCoreTests/VoiceQualityRouteSecurityTests.swift` | 209-319 | 6075 | `4ae864733e95ac79cc6585c523913651ba11170d7796ab72a9eea5b292b1d176` | `42701ce54d290aa6f9d68cfe25dc3e80aaa40437` |
| `20-VoiceQualityRouteSecurityTests-part4.patch` | `Tests/ZeusCoreTests/VoiceQualityRouteSecurityTests.swift` | 320-463 | 6056 | `70fa45dcb108803e459204abbb189abf68739097ef09a588653103bac309d34e` | `42701ce54d290aa6f9d68cfe25dc3e80aaa40437` |
| `21-VoiceQualityRouteSecurityTests-part5.patch` | `Tests/ZeusCoreTests/VoiceQualityRouteSecurityTests.swift` | 464-476 | 989 | `7f798945cb2be2640f8dff8fe83939a82816df1b1e3b5a7e21b62f0b42788a11` | `42701ce54d290aa6f9d68cfe25dc3e80aaa40437` |
| `22-VoiceQualityNoUpstreamRouteTests-part1.patch` | `Tests/ZeusCoreTests/VoiceQualityNoUpstreamRouteTests.swift` | 1-11 | 938 | `fc9c41deda2cc794591ab8f8124eba715ea54ea0089a51e1b16332cee06f03af` | `65dd09efaedf66f646d3593538f239bfef8385cf` |

