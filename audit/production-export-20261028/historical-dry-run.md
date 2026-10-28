# Historical reconciliation dry run

Offline proposals from the completed export. No historical corrections were executed.

All original receipt IDs, references, amounts, dates, cycle references and frozen charges are retained in historical-dry-run.json.

Examined 153 patients, 201 stays, 289 receipts and 176 known cycle groups.

35 missing stay cycle fields have exactly one saved segment owner. These are metadata-only proposals, with zero financial delta. The shared read resolver can use that evidence without a historical write.

All 80 unestablished receipt associations (79 missing plus one unmatched explicit) remain unallocated: 189,200.00. This includes the 67 single-known-cycle receipts / 165,600.00; one remaining cycle and aggregate agreement do not prove complete admission history.

The strict resolver can differ from a saved allocation without establishing that the saved allocation was wrong. Candidate due/credit arithmetic in the JSON uses frozen totals only and authorizes no collection or refund.

Ledger net before and after every proposal: 909,550.00. No receipt is reassigned, merged or removed. All frozen charges remain unchanged.

5157: retain both explicit stay groups and their 1,200.00 frozen charges. The unmatched 1,200.00 receipt matches both snapshots; original admission/placement evidence must establish the authoritative cycle and whether both charges are valid.

5219: all three untagged receipts / 6,800.00 require original allocation evidence (4,400.00 is a subset). The saved 2,200.00 refund is not authorized.

The 800.00 stored-field conflict requires original invoice evidence. Both active-stay/discharged-label conflicts require occupancy evidence. 5255 needs canonical display resolution, preserving conflicting source marks. 5251 remains unexplained because neither screenshot response was saved in this export.

The ten duplicate-reference groups remain candidates. No source payment ID duplicates exist; placeholder/split references must not be deduplicated automatically.

| Patient pseudonym | Prior fingerprint | Findings | Receipt allocation review | Metadata-only proposals |
|---|---|---|---:|---:|
| patient_6b5574d907873b2f94bf79a3dbb64af87bee44b6c2bfe2a36c926ac9563b625f |  | ambiguous_legacy_receipts | 3200.00 | 0 |
| patient_de693c49ed90c8aa2233b8b3c107eab16828be5111fc6d77d5b99ec3f7f8beaa |  | No recorded inconsistency established | 1200.00 | 1 |
| patient_25719c314b2d453abd0a08fb07fb4ef3870e97b9dee9bb5b5e8e724052ba4624 |  | No recorded inconsistency established | 6400.00 | 1 |
| patient_ecf703ab24a6f8287eec1e17d9af5a5e59f8f3eb395d9cf8d98bc505a95aecc3 |  | duplicate_reference_candidate | 0 | 0 |
| patient_83561823d0f6080afb81016816a498f12a0d50a71fb6a1434711315ddeae7b5b |  | No recorded inconsistency established | 1200.00 | 1 |
| patient_953e2c4256f5073f6bcffcf9f349cce9ac538dc778a3a3c47edd15d3d7817ec3 |  | No recorded inconsistency established | 2000.00 | 1 |
| patient_00cc66a86a96f1d0c60759c213917c3af119c9532c3ca86986197bd9a7e80183 |  | No recorded inconsistency established | 3200.00 | 1 |
| patient_c2cb34ba3220ab03fa66bf4bd050182daab11c776ed55556131c9100c0073719 | 5219 | ambiguous_legacy_receipts, duplicate_reference_candidate | 6800.00 | 0 |
| patient_d9d941844a1f1a2523b9806dfc76539772a0fa9514f9ec5a7fdde62f06f8ce28 |  | No recorded inconsistency established | 4000.00 | 2 |
| patient_83306d8b95362bf0d4b35c8f96fcb87e8968e12a9ac02b90df39a68d7c7eb0f3 |  | No recorded inconsistency established | 800.00 | 1 |
| patient_9c67f814e6eceb584b10f125a57dd414df17e4a43f213feb4491d9781755c48e |  | No recorded inconsistency established | 2100.00 | 1 |
| patient_7b68bc51bb57fb54c1bf68404e99cc47584c5635ab1a8d3895fc3f16d5b1e620 |  | No recorded inconsistency established | 1200.00 | 1 |
| patient_b893817340a06428a9a786a2b6f8b74885760c516e051840cd253b8d701a887f |  | No recorded inconsistency established | 4800.00 | 1 |
| patient_8b290d418e19bb4eb8255e04a9fd28a9fa05b1de2a4d4c049759f5f8021bc722 |  | duplicate_reference_candidate | 12000.00 | 2 |
| patient_515d646fb25b2081925ad51fcca6ec0de14754a711f52a576df975c8a1798193 |  | No recorded inconsistency established | 7600.00 | 0 |
| patient_2b827ab65a747a2007abf1f11fa55510bb0ab781fbbdaf8f7aa86ec2d84cfbb6 |  | duplicate_reference_candidate, patient_snapshot_arithmetic_conflict, saved_history_absent | 4000.00 | 0 |
| patient_d14a04a7f527be32c313ffbf5dcf8382a233117dccf636335eaa369b6c00104e |  | duplicate_reference_candidate, saved_history_absent | 8000.00 | 0 |
| patient_deadae93b7ad8668f526c315a6015b549ae9b2d6c0b595388fa8d61321d52217 |  | No recorded inconsistency established | 7800.00 | 1 |
| patient_0d8fd2c423d5d6767d960a88e6997a9f0b6d8608b0ab9d826ea9d7876a5db7e3 |  | No recorded inconsistency established | 10000.00 | 0 |
| patient_c063bd7202f67483f7a21df4f840e0814f6577047295b3897cafa20fdbc78206 |  | No recorded inconsistency established | 4400.00 | 1 |
| patient_6bed0cf4b879eb7a4b279054f41a2c8256168278684887f93bdac0a578c4d529 | 5157 | ambiguous_legacy_receipts, stay_snapshot_cycle_conflict, unmatched_explicit_receipt | 2400.00 | 0 |
| patient_805db8a524aaa4c9bba149de373a147cb525e5a0f75f95bb78d8ad1218059779 |  | No recorded inconsistency established | 800.00 | 1 |
| patient_7005ba542f6a8976ca56888833135ea6c16994d5d0566002be1fcdccf55d4f46 |  | No recorded inconsistency established | 2100.00 | 1 |
| patient_bd5e0f89325f354bd7fc39eac72ac2ff45a1399cfea4fccab7dc643357312638 |  | No recorded inconsistency established | 0 | 1 |
| patient_717688a350df7a29901c9569bb29a4466e5ca0371a7ef996e21ed4640af9d344 |  | No recorded inconsistency established | 400.00 | 1 |
| patient_3e1f41593901e0ee2d0032332fb722422330e374c56b8e3e148d12b3ccb5fb42 |  | No recorded inconsistency established | 0 | 0 |
| patient_6ad3c6a128bce54672b032ee01dca63f8aa763090e33a7dfa84d942178ef6eda |  | No recorded inconsistency established | 2800.00 | 1 |
| patient_4a8f88b0031ba568d24b725f9bb226870bfeec8205daa98bf611940891dabd9f |  | No recorded inconsistency established | 4800.00 | 1 |
| patient_f3520601e5778961ddcba22ae25bba1531b43f9596e1eb03a4e7069cce6a1be9 |  | No recorded inconsistency established | 4900.00 | 2 |
| patient_633d39f7b9a3b9e710ad1d5071588926c85174b3ff7b2b3218ac0d8698c18e01 |  | No recorded inconsistency established | 0 | 0 |
| patient_78fc6740020f8ac41e5dcaa913704e15cabf27ff5f159d85ffc01b2c240145af |  | No recorded inconsistency established | 1200.00 | 0 |
| patient_85ee49249c90517e5b89193955f8e1f8a043b62a5b89652583f80d1ffc83dbb3 |  | ambiguous_legacy_receipts | 3000.00 | 0 |
| patient_faba93b9ef6eb11222631f57b7924d70c313653773b9ca32f08e7c28fb57408d |  | No recorded inconsistency established | 2800.00 | 0 |
| patient_721cd8e7917ac0443a891cd808a339989ee06e0d36e1c18176648e139acd45f1 |  | ambiguous_legacy_receipts, duplicate_reference_candidate | 2200.00 | 0 |
| patient_53fdefa5a38043fe9539bf0371a661e7cf1709d704d332636a1202118f1c3501 |  | No recorded inconsistency established | 3200.00 | 0 |
| patient_39ab0382ee07c96337d8dc4c8c98fbb45bea0cc3be0936b8493b4063b3085aa8 |  | saved_history_absent | 600.00 | 0 |
| patient_50ddd41bb8fb7c42c71390bb95045249aa0f312f9adf8d74211fc53689275d93 |  | duplicate_reference_candidate | 1600.00 | 0 |
| patient_c4b54c5b5ff61deb806ed2908ac7aa0d831aec5fbd4e491d41d7be558ccfb248 |  | No recorded inconsistency established | 0 | 0 |
| patient_612197b001c940600ef4c45b01a9128bc47de5fcaadc3b796a709b69a9980546 |  | saved_history_absent | 1600.00 | 0 |
| patient_c37f0ce70cde482e7cf0dcac7e11df074d58e0042e1fc4bcf67e4cb4274d6927 |  | No recorded inconsistency established | 800.00 | 1 |
| patient_59247f5a25da62636990a87f730b682d7e9d4deb50280f01e857094d894684b1 |  | No recorded inconsistency established | 6300.00 | 0 |
| patient_444f20b7309373ca0eb8fafbb48a0b21d10694b353f6d83b0f2b299859c796e1 |  | No recorded inconsistency established | 800.00 | 0 |
| patient_63dcf4a3c7541b7699a1a83682e8c0bef42c66f5db2f08d5b31799d95850d979 |  | No recorded inconsistency established | 3200.00 | 1 |
| patient_5bb796e9fb50754ee30d177943456d826e28a3b687dd352688ee7f891fde24e5 |  | duplicate_reference_candidate, saved_history_absent, stay_cycle_evidence_incomplete | 400.00 | 0 |
| patient_3f37b89b8d57866fddf548858c4424a0a48de0164ce03113eb27168c473895b3 |  | No recorded inconsistency established | 7200.00 | 0 |
| patient_4a7ae7e19d38c82d3392e99bb81fc70c110aec9dc5c1b54558c2e13891edda00 |  | No recorded inconsistency established | 2800.00 | 1 |
| patient_50643722c50a349cd9dcc400f7536835fce7e702bc311dc40bbd5095079159cc |  | No recorded inconsistency established | 0 | 0 |
| patient_241897ff4b75649a2680dbf18d8a025b1ed7578b88eafa292bafa4b03fc79b82 |  | No recorded inconsistency established | 0 | 0 |
| patient_792524122c079082b6d7067b84527d7ab3dfd609b2d2734d4d9088a24718e9f4 |  | No recorded inconsistency established | 4800.00 | 0 |
| patient_9197910d185dbf6bb6742eb3d79257003f26c01b8e2b29500b1bd0daa2bce0ea |  | No recorded inconsistency established | 0 | 0 |
| patient_2efe8aa1c45325f7941d6cc0e39f1ebc6eff67f6fd53974fea70927c921937ab |  | No recorded inconsistency established | 0 | 0 |
| patient_38f2e5d77cc42fbd21ef29ac3eff111914f43fae5e2728faaecd3829ab41a4bf |  | ambiguous_legacy_receipts | 4800.00 | 0 |
| patient_225fdf51c1ca39bd54e8fb76da40517a7e7ca49a427a91ca3910168d3ccf0877 |  | duplicate_reference_candidate | 0 | 0 |
| patient_9d9aa6bcc6ab28b909c9742901a4351b5881229029eb9a02fbb750094ef3b4f1 |  | No recorded inconsistency established | 4000.00 | 0 |
| patient_c92e21a71577144e110de3122f6f47d4b9f3af9919e5b023e330bee5881ac6f5 |  | No recorded inconsistency established | 2800.00 | 0 |
| patient_3948163b3bb40054f90fb1af3115c9177720884b47957d303611f3dfef89589a |  | No recorded inconsistency established | 1600.00 | 1 |
| patient_1496676087a28a85be7aa47d5fa9f749f1392bcf4597b2482503db6368c61d4e |  | duplicate_reference_candidate | 1600.00 | 0 |
| patient_f6ad499cfd306a24392e64bf960f78489d82c3a89abe461cc4493631d6bd9df4 | 5149 | discharged_with_active_stay | 2400.00 | 0 |
| patient_4c401bf4f253b98b9548f5cd5115f1d943d7be931b0985980789638466b6d881 |  | No recorded inconsistency established | 1600.00 | 0 |
| patient_77b05d52531656ec282d450d3b6b54f76846120b4d423fe84603c7c3be87e774 |  | ambiguous_legacy_receipts | 400.00 | 0 |
| patient_058cdb0626da8a55ba4870261edc1e13846a4cc045b68df71e315241836e2832 |  | No recorded inconsistency established | 1200.00 | 0 |
| patient_b70d8857e1988b865b92ba891927192504cced15a852be4a02aa4e65e60e63fe |  | No recorded inconsistency established | 600.00 | 1 |
| patient_e5f031cf174ce4b806eabb2fc77357539550055c0b96c0d3eee4f3921f9d28d6 |  | No recorded inconsistency established | 4000.00 | 0 |
| patient_532c02fbdd5a27b5680c018e214ecddc5a60d7ee8da68cfa2ec87ee81a7413a6 |  | duplicate_reference_candidate | 2800.00 | 2 |
| patient_c3924aefa26d288741e5df5a7b0232c897715da782ca9c1979215e6cda8a6737 |  | No recorded inconsistency established | 2400.00 | 1 |
| patient_65242b4c931e60cdf7d4e1a1a4112fcb67bc3ff378ee73e918abdd5c28b91ddf |  | No recorded inconsistency established | 400.00 | 1 |
| patient_b289a427012b9389a195183dcd2a68e97de6016853a0bfe7af7bcf21bc7566cc |  | No recorded inconsistency established | 1600.00 | 1 |
| patient_09b3782ab6fc78d6b63b33a280d4587479669ed54c33c371be26d46d99dad219 |  | No recorded inconsistency established | 400.00 | 0 |
| patient_63b4f30000cd918be0e8d87325eded97df4a39f62045cb9fa885cc312e6b630b |  | No recorded inconsistency established | 1200.00 | 0 |
| patient_a70a9578185d230128e2bd805198e59777dd1a58587b4a320fdd50bc7960c6c0 |  | No recorded inconsistency established | 200.00 | 1 |
| patient_35a834e448cbdcca7713a407047d54fd806a9217ac418df4ce9c038f3abe779c |  | duplicate_reference_candidate | 0 | 0 |
| patient_93c6bd482ad429e3b2bc8932a1f3b55fe8ce6e6ffd012394439daec6edff3f5b |  | ambiguous_legacy_receipts, duplicate_reference_candidate | 800.00 | 0 |
| patient_970eaf593b0b09b79010f8cdb46c92bd878d23fdb52d324356d97e8ede1dcf1b |  | No recorded inconsistency established | 0 | 0 |
| patient_3912930e77a1150773b0ac11e94a00757f4d32a84a38179f675289920c80deee |  | No recorded inconsistency established | 600.00 | 1 |
| patient_1e9e5ba06614f45357fcd7a99e1c76add2676c3fe9b45d6e0b427acef2b30664 |  | No recorded inconsistency established | 0 | 0 |
| patient_d0d02bc777f0a615355981df6074634bd06fb4cfde7117e7e90a329e262c8aaa |  | No recorded inconsistency established | 0 | 0 |
| patient_2b77d996004bdc6d478e98e8ecf59f1a1e0444b3c5ef6b6fbd1760649319c98e |  | No recorded inconsistency established | 0 | 0 |
| patient_175ad05fc1b5dfb78ba38f466879c720881b2f1149cf7946c1359bdb2c9673a5 |  | No recorded inconsistency established | 0 | 0 |
| patient_04dedaddd957ccdcc807d0604476cc2842f4e13873fdff5a111a030579de79e7 |  | No recorded inconsistency established | 0 | 0 |
| patient_5fbba3c32755f4fbbcc2757b8d5020ca051f9ab9f7f9a525744980f7cbbaf337 |  | No recorded inconsistency established | 0 | 0 |
| patient_773a58130eae534c13fd920228d7ed8e1ba1c3e3f1d7767df17f1a771312161f |  | No recorded inconsistency established | 0 | 0 |
| patient_3912da469c57072cfd076241c36e602dea7f32b33bebd635569558a5ba57da57 |  | duplicate_reference_candidate | 0 | 0 |
| patient_2030fdffe6709eff91a1fb55b3e850037f3d6ad618bffe67cbae2eb85f91470a |  | discharged_with_active_stay | 0 | 0 |
| patient_ddf0863ada6e457dc79f118454ea585f1a100a1c10c36f06e2912791088b104b |  | No recorded inconsistency established | 0 | 0 |
| patient_34ec2d82085aa6fa79e3135e72bfd9daeac3a49c760b9e496eaad30adb07a7bc |  | No recorded inconsistency established | 0 | 0 |
| patient_cab151a7c9f288ba5aa885ee7fa1498347c63a40193bd2bc99399cb9d4ff32a3 |  | No recorded inconsistency established | 0 | 0 |
| patient_ac30c8ce77bdd27cd600f1373e9e9b5d0ab9578de488ba763444106a534463bb |  | No recorded inconsistency established | 0 | 0 |
| patient_956a4b6d33a0ef58d8c53fe5bbe83e3beb27665f3591629256d9384a0bb8a7aa |  | No recorded inconsistency established | 0 | 0 |
| patient_36c0804598e04f71d55ea492515af324342eb139ab28b777f6db4310d805039f |  | No recorded inconsistency established | 0 | 0 |
| patient_419497aa0b13652c4645cd1ba7cca54ddf275d797824cf88411317e505712777 |  | No recorded inconsistency established | 0 | 0 |
| patient_60457f493521506fa293e2ad7a51f61c27513a2637ed00f11ce6992f93bc8fad |  | No recorded inconsistency established | 0 | 0 |
| patient_4e24aa572f13eb9c540532bc620dccdf4c1a534560098c1f76e2557641ed7474 |  | No recorded inconsistency established | 0 | 0 |
| patient_550ee6fdc1c62907958f4a87a6c23e589fe9725f468f9dc280c3b4018a85b3a3 |  | duplicate_reference_candidate | 0 | 0 |
| patient_e0d4054b9a0170a300c72216d7fc64055c1c67295a9bf1cc2fef5235b4604d81 |  | No recorded inconsistency established | 0 | 0 |
| patient_029c29a3789262cb857a57f5a65bc6fcfc86513121c4ecdcd73efbe3e3792a69 |  | No recorded inconsistency established | 0 | 0 |
| patient_a20e5a288db09cb94021f5221edce888e2e5cafe2d79064ab9aa36705ea664c0 |  | No recorded inconsistency established | 0 | 0 |
| patient_a666497c620936f98ee4b4a1c7de786e4322a61cd7cd18b188fb067810249c98 |  | No recorded inconsistency established | 0 | 0 |
| patient_e8313a5e8cb605b41507418bdb474c591eaf1229d1d68c7bb95ee3659a6bdad6 |  | No recorded inconsistency established | 0 | 0 |
| patient_8b6e162cf6e179065c18a651d4b77145431be2a135e74872548b29b9b1a675f8 |  | No recorded inconsistency established | 0 | 0 |
| patient_28a4d2e26bdb36ea94b2da6c1f857824baef7d2dfb67797f4bd5ca4b9e0b1bef |  | No recorded inconsistency established | 0 | 0 |
| patient_45389c1fe681d23fe5d2dc5730e5d62bb2a7e813026bacd4fe33f45bf01b6e9a |  | No recorded inconsistency established | 0 | 0 |
| patient_ddf4b3e54393971ea4eb1a248559d8665e506256031b98bad5e5594086016bdc |  | No recorded inconsistency established | 0 | 0 |
| patient_9c895b9b619ca2ead2faf702c04e9b9bdb5de5c6bbe94def72e299f58e7a711f |  | No recorded inconsistency established | 0 | 0 |
| patient_ebec5d0f35b20a8107a168294e4f75dac587a9d2d0e1a2d9c977587c698d0026 |  | No recorded inconsistency established | 0 | 0 |
| patient_185150fa2e6065a91cab0b80068205cc64b458314cc52efb2871855d5ef96446 |  | No recorded inconsistency established | 0 | 0 |
| patient_d67485b056162aae90e016ebfb9f356efdfe08db83defcc305c43836c75e1640 |  | No recorded inconsistency established | 0 | 0 |
| patient_f1b0c08e017f5fe29d6a5b94961fb6967e08ea62086242afe621f12750da92d8 |  | No recorded inconsistency established | 0 | 0 |
| patient_c7f711f52cced10402253e6cd89e8c1968022c86745c3af59ad0bb628ccd129a |  | duplicate_reference_candidate | 2400.00 | 0 |
| patient_1bd06072ebfad36dd96ee8a983cb55f81903e5852521cd1a6be9da04ae1cc5d0 |  | No recorded inconsistency established | 0 | 0 |
| patient_5de05e884e84c33ba0293aa93944ce00644fc0f10881ec2507dd639f478fb21d |  | No recorded inconsistency established | 0 | 0 |
| patient_3e1481daebf908422cfd05c16e19db7fc79c197bab5c361287c6900774078670 |  | No recorded inconsistency established | 0 | 0 |
| patient_fc6f801b57c496a2f425a83364d103bf5f06bb7d0e7cfcd9381b9c0eafa74864 |  | duplicate_reference_candidate | 0 | 0 |
| patient_01f6d609cb0f901354a947edf55332e66109bd002e6d125c7b32993ea0e7aa6d |  | No recorded inconsistency established | 0 | 0 |
| patient_7d3595cd94538002fb9b62d8130c52ff036981fef1243fce8db873d756f52d98 |  | No recorded inconsistency established | 0 | 0 |
| patient_6bd6f98d7b99f1bc598826b21086b6e4762b0cd02f6c08d3758859338f090604 |  | No recorded inconsistency established | 0 | 0 |
| patient_eb13e76eac3b69ff457a1f09e1a319fa69e9fa4ace943ecd67e4201e6497386f |  | duplicate_reference_candidate | 0 | 0 |
| patient_4455394e70770e3cf381bb096870f3cb8e4da72c1be7ce99669f2d2a3790b805 |  | No recorded inconsistency established | 0 | 0 |
| patient_24afcbbe03ebb83569276377548087f93f040d8b83e7687b83dd084c8efb682b |  | No recorded inconsistency established | 0 | 0 |
| patient_66c71f6a725107e1e9ad231d70be8ab88bcede99b1a75797915f24304e69bf59 |  | No recorded inconsistency established | 0 | 0 |
| patient_62542efbf687a3a1d64ef8d3d843b39b92991b60d9140bc431f8e86329cd94d7 |  | No recorded inconsistency established | 0 | 0 |
| patient_78e1dab865ce6ab1f60d334740885d8849cdeec1eefd75895f744d4c1574b99f |  | duplicate_reference_candidate | 0 | 0 |
| patient_9e367c8f7b4275efb7f6a8b6baf456fefaa50147e7960ed0421c277d4b698a60 |  | No recorded inconsistency established | 0 | 0 |
| patient_c965d8642ce18fa6bf634b63d92058f6cd112d3f250f7f86010e994b77659481 |  | No recorded inconsistency established | 0 | 0 |
| patient_9f3cfb7a868636fe60a0032959e68e228f93b1e18918fec217cf3afb996eeba6 |  | No recorded inconsistency established | 0 | 0 |
| patient_b140ee5c4e84cd4a6ef65a444679f78b22cf16d58e3a17871f30aa2c8a3e58f8 |  | No recorded inconsistency established | 0 | 0 |
| patient_b3c45ad289fc637f00e5f0d062574466ac0c176a7ed9cb527cf92aa77c2372f3 |  | No recorded inconsistency established | 0 | 0 |
| patient_9832e785ed3daa61e1344f955721f283baa3f00748dda423e65d7af56c587bca |  | No recorded inconsistency established | 0 | 0 |
| patient_a3d3de25c380dcea175e0329e6886bba6387b8ac40e903a90a6249852ff6c1ce |  | No recorded inconsistency established | 0 | 0 |
| patient_5d946a47354885ec4dce3e900dcdbc2bc60161fbe4359951042f2bf2975e1433 |  | No recorded inconsistency established | 0 | 0 |
| patient_6a3a75bd7f8649a1ceb9c3078de7ef411d370bb539a375407e18e6cbb65f3986 |  | No recorded inconsistency established | 0 | 0 |
| patient_d81165ad98055aebda1464f5d1cb4b5bec1cdc863a5537b7b96e54c52288c4e8 |  | No recorded inconsistency established | 0 | 0 |
| patient_a2e59ea4027c4b64b531c6b7079247d67f6cddb2398254754c68bec052adf76e |  | No recorded inconsistency established | 0 | 0 |
| patient_ff760fae1c3d3bf9ac31b7a4a21d2b2c5f0146aabb1c3e7a3457e8b335d6937e |  | No recorded inconsistency established | 0 | 0 |
| patient_97c2814348aab6aa99a7f79b1af90170c2180dfcbb54ecbd25c3053362bc34e5 |  | No recorded inconsistency established | 0 | 0 |
| patient_8f111e9bf2ee0cd2ca858921cb2a8977b559a9a002a2342c5e9a446330cd955d |  | No recorded inconsistency established | 0 | 0 |
| patient_199b40eab08e2f4848ae5c67457bf79b875ce0e893fc07cc3389905f9da8c268 |  | No recorded inconsistency established | 0 | 0 |
| patient_388aae094c385ee3f8ff1bb89f5907fbbf46df9da7117c81003d9d1330db687e |  | No recorded inconsistency established | 0 | 0 |
| patient_c60d396e765e65e8abccaab90c5ec940bcfbfaad3f869d33e2862d6608d6e595 |  | No recorded inconsistency established | 0 | 0 |
| patient_680b8fa0272aff80e3634ce16f35b29dbeb79e2839c3379782333afa6715397a |  | No recorded inconsistency established | 0 | 0 |
| patient_a772137a11c41e33dfe5608677108c6a42685c638b389a0b2a7446c074daf0d4 |  | No recorded inconsistency established | 0 | 0 |
| patient_7754bcb6fc781cb8daab9a9cb4cd2a5072fa8de8d95b672ceeb2385d462c862b |  | No recorded inconsistency established | 0 | 0 |
| patient_73da9fd596745ae19283f1a56329725ab959d37a866d9674d1bc88171d07fb7d |  | No recorded inconsistency established | 0 | 0 |
| patient_9fec28a8578d9e32b9b3c2ba8db4dc89feee79f67d6bf5cec0f4ca1d1de1cd0b |  | No recorded inconsistency established | 0 | 0 |
| patient_7be64764059efb13f0ba66f869d928740e453a05219a9fd54ca83365de794632 |  | No recorded inconsistency established | 0 | 0 |
| patient_672d5b9cb5088bddcc4f0c444b06069ef85de4aec3d4edd59a1b52183e1819e5 |  | No recorded inconsistency established | 0 | 0 |
| patient_5bfb24c237f7e437d0a3aa53c2ba8c4f58dd36101b5a450d742d0eb40f11d1e8 |  | No recorded inconsistency established | 0 | 0 |
| patient_943e7420171add3148b1bf8fbc47c2dbb867ed0d253ff3258b92de0e783dc69b | 5251 | No recorded inconsistency established | 0 | 0 |
| patient_02b5c8270fe0192a715ecfb0b9f297a6f69e3c47ffcc2bb081f0651f9a2caaba |  | No recorded inconsistency established | 0 | 0 |
| patient_93ed7e845ac1183e24d1e10ecb691cb6184e5ea25046d1efca5083ce18c5453a |  | No recorded inconsistency established | 0 | 0 |
| patient_4d9e942cd298dd405073b5b49da18e6220fc609260ea5e11fdfca27af7efc956 |  | No recorded inconsistency established | 0 | 0 |
| patient_245b79d617576bb618c4eee92781768ea262fcf9317958a7281ab5b47ef973f9 | 5255 | overlapping_attendant_marks | 0 | 0 |
| patient_485c2cbb54f87a630f4e020cf348e83a4213f52e5536bcbdd7261e2fb49fc9f8 |  | No recorded inconsistency established | 0 | 0 |
| patient_8081598f2ca629df5dd3e214011fd30a99dc4c2bccc10cdbb3687cce1a835408 |  | No recorded inconsistency established | 0 | 0 |

Before any eventual correction: verify production identity and revision, create and restore-test an independent backup, review this dry run against original private evidence, require operator/reason and change history, execute a tested transactional/idempotent migration, compare before/after frozen totals and rerun. No such migration is executed or authorized by this artifact.
