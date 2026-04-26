// L10n.swift
// Centralized string catalog for Memory Tunnel.
// Supports English and Simplified Chinese via in-app language switcher.
// Usage: L.flashback, L.memoryLanes, L.startAMemoryLane, etc.

import SwiftUI

// MARK: - Language Setting

enum AppLanguage: String, CaseIterable, Identifiable {
    case en = "en"
    case zhHans = "zh-Hans"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .en: return "English"
        case .zhHans: return "简体中文"
        }
    }
}

// MARK: - String Catalog

enum L {
    @AppStorage("appLanguage") private static var lang: String = "en"
    private static var isCN: Bool { lang == "zh-Hans" }

    // MARK: App Chrome
    static var flashback: String { isCN ? "今日闪回" : "Flashback" }
    static var memoryLanes: String { isCN ? "记忆空间" : "Memory Lanes" }
    static var cancel: String { isCN ? "取消" : "Cancel" }
    static var done: String { isCN ? "完成" : "Done" }
    static var back: String { isCN ? "返回" : "Back" }
    static var save: String { isCN ? "保存" : "Save" }
    static var skip: String { isCN ? "跳过" : "Skip" }
    static var edit: String { isCN ? "编辑" : "Edit" }
    static var delete: String { isCN ? "删除" : "Delete" }
    static var share: String { isCN ? "分享" : "Share" }
    static var send: String { isCN ? "发送" : "Send" }
    static var tryAgain: String { isCN ? "重试" : "Try again" }
    static var continueBtn: String { isCN ? "继续" : "Continue" }
    static var verify: String { isCN ? "验证" : "Verify" }
    static var next: String { isCN ? "下一张" : "Next" }
    static var previous: String { isCN ? "上一张" : "Previous" }
    static var settings: String { isCN ? "设置" : "Settings" }
    static var language: String { isCN ? "语言" : "Language" }
    static var resetAccount: String { isCN ? "重置账号" : "Reset Account" }
    static var resetAccountConfirm: String { isCN ? "确定要重置账号吗？所有本地数据将被清除，你需要重新登录。" : "Are you sure? All local data will be cleared and you'll need to sign in again." }
    static var deleteAccount: String { isCN ? "永久删除账号" : "Delete Account" }
    static var deleteAccountButton: String { isCN ? "永久删除" : "Delete Forever" }
    static var deleteAccountConfirm: String { isCN ? "此操作不可撤销。所有记忆空间、照片、语音、文字记录将被永久删除。如果你是某个记忆空间的创建者，对方也会失去访问权限。" : "This cannot be undone. All your memory lanes, photos, voice clips, and text will be permanently deleted. If you created a memory lane, your partner will lose access too." }
    static var resetAccountButton: String { isCN ? "重置" : "Reset" }
    static var account: String { isCN ? "账号" : "Account" }

    // MARK: Splash
    static var tunnelingIn: String { isCN ? "正在穿越记忆..." : "tunneling in..." }

    // MARK: Welcome Walkthrough
    static var walkthrough1Headline: String { isCN ? "相册深处被遗忘的碎片" : "your photos hide\nburied memories" }
    static var walkthrough1Subtext: String { isCN ? "穿越相册，拾起记忆碎片" : "the tunnel digs through your camera roll\nand surfaces photos you forgot" }
    static var walkthrough2Headline: String { isCN ? "共创记忆空间" : "build a memory lane\nwith someone" }
    static var walkthrough2Subtext: String { isCN ? "只属于两人，记录分享照片、语音和笔记的私密空间" : "a shared space for photos, voice clips,\nand notes. just for you two." }
    static var walkthrough3Headline: String { isCN ? "分享碎片" : "share what you find" }
    static var walkthrough3Subtext: String { isCN ? "分享来自1,230 天前的惊喜" : "1,230 days ago.\nshare the surprise." }
    static var getStarted: String { isCN ? "开始" : "get started" }

    // MARK: Onboarding Auth
    static var appName: String { "Memory Tunnel" }
    static var appTagline: String { isCN ? "为了那些不该被忘记的" : "For the people who matter most." }
    static var phonePlaceholder: String { isCN ? "+86 (手机号)" : "+1 (555) 555-5555" }
    static var enterOTPPrompt: String { isCN ? "请输入发送到手机的6位验证码" : "Enter the 6-digit code\nsent to your phone." }
    static var changeNumber: String { isCN ? "更换号码" : "Change number" }
    static var whatShouldFriendsCall: String { isCN ? "朋友们怎么称呼你？" : "What should friends call you?" }
    static var yourName: String { isCN ? "你的名字" : "Your name" }

    // MARK: Photo Permission
    static var seeThePeople: String { isCN ? "找出你在乎的人" : "See the people\nyou care about" }
    static var photoPermissionBody: String { isCN ? "Memory Tunnel 会在你的设备上私密地扫描照片，任何数据都不会离开你的手机" : "Memory Tunnel scans your photos\non your device, privately.\nNothing leaves your phone." }
    static var allowPhotos: String { isCN ? "允许访问照片" : "Allow access to Photos" }
    static var skipThisStep: String { isCN ? "跳过" : "Skip this step" }

    // MARK: Smart Start / Face Scanning
    static var whoStayClose: String { isCN ? "你想和谁保持联系？" : "Who do you want\nto stay close to?" }
    static var smartStartBody: String { isCN ? "Memory Tunnel 可以从你的照片中找到常出现的人——完全在本地处理，保护隐私" : "Memory Tunnel can suggest\npeople from your photos —\non your device, privately." }
    static var findingPeople: String { isCN ? "正在寻找你在乎的人…" : "Finding the people you care about…" }
    static var takingASec: String { isCN ? "稍等一下..." : "taking a sec..." }
    static var skipForNow: String { isCN ? "先跳过" : "skip for now" }
    static var peopleFromPhotos: String { isCN ? "照片中的人" : "People from your photos" }
    static var startAMemoryLaneWithSomeone: String { isCN ? "和一个重要的人开启记忆空间" : "Start a memory lane with someone who matters." }
    static var theirName: String { isCN ? "对方的名字" : "Their name" }
    static var startAMemoryLane: String { isCN ? "开启记忆空间" : "Start a memory lane" }
    static var skipDoLater: String { isCN ? "跳过——之后再说" : "Skip — I'll do this later" }
    static var noPhotosFound: String { isCN ? "未找到照片" : "No photos found" }
    static var goBack: String { isCN ? "返回" : "Go back" }
    static var saveMemory: String { isCN ? "保存记忆" : "Save memory" }
    static var savingMemory: String { isCN ? "正在保存…" : "Saving memory…" }
    static var memorySaved: String { isCN ? "记忆已保存" : "Memory saved" }
    static func readyToInvite(_ name: String) -> String { isCN ? "准备邀请\(name)吗？" : "Ready to invite \(name)?" }
    static func invite(_ name: String) -> String { isCN ? "邀请\(name)" : "Invite \(name)" }
    static var saveForLater: String { isCN ? "稍后再说" : "Save for later" }

    // MARK: Scan Progress Ring
    static func facesFound(_ n: Int) -> String { isCN ? "找到 \(n) 个人" : "\(n) face\(n == 1 ? "" : "s") found" }

    static var scanPhrases: [String] {
        isCN ? [
            "正在穿越记忆...", "翻老照片中...", "看看谁藏在这里",
            "穿越相册时空", "寻找熟悉的面孔", "每张照片都有故事",
            "深入档案库", "好多久远的照片", "算法正在发力",
            "你有个宝藏相册", "在回忆里挖宝", "加载怀旧片段中...",
            "回忆美好时光", "这么多珍贵瞬间", "这张好好笑",
        ] : [
            "tunneling through memories...", "dusting off old photos",
            "who's been hiding in here", "time traveling ur camera roll",
            "finding familiar faces", "every photo tells a story",
            "deep in the archives", "some of these go way back",
            "the algorithm is vibing", "ur camera roll is a goldmine",
            "digging through the feels", "nostalgia loading...",
            "remembering the good times", "so many moments saved",
            "this one sparks joy",
        ]
    }

    static var deepScanPhrases: [String] {
        isCN ? [
            "记忆轮盘启动", "深入记忆宝库", "寻宝模式开启",
            "越挖越有好货", "翻出被遗忘的宝藏", "我们在翻箱底了",
            "稀有照片即将出土", "好照片都藏在这里", "回忆大奖加载中",
            "2019年的你留了好东西", "考古你的相册", "只挖最深的",
        ] : [
            "memory roulette activated", "going deeper into the vault",
            "buried treasure mode", "the deeper we dig the better it gets",
            "pulling up forgotten gems", "we're in the archives now",
            "rare photo drop incoming", "this is where the good ones hide",
            "throwback jackpot loading", "ur 2019 self left some bangers",
            "excavating the camera roll", "deep cuts only",
        ]
    }

    // MARK: Today Tab
    static var hintTitle: String { isCN ? "在你的相册中找到了这些照片" : "the tunnel found\nphotos in your library" }
    static var hintSwipe: String { isCN ? "滑动浏览" : "swipe to explore" }
    static var hintTap: String { isCN ? "点击添加到记忆空间" : "tap to add to a memory lane" }
    static var hintShare: String { isCN ? "分享你的发现" : "share what you find" }
    static var gotIt: String { isCN ? "知道了" : "got it" }
    static var thatsAllForToday: String { isCN ? "今天就这些" : "That's all for today" }
    static var comeBackTomorrow: String { isCN ? "明天回来看看新的记忆" : "Come back tomorrow for new memories" }
    static var todaysMemory: String { isCN ? "今日记忆" : "TODAY'S MEMORY" }
    static var firstMemory: String { isCN ? "第一段记忆" : "First memory" }
    static var birthdayToday: String { isCN ? "今天生日" : "Birthday today" }
    static var itsBeenAWhile: String { isCN ? "好久不见" : "It's been a while" }
    static var sendAMemory: String { isCN ? "发送一段记忆" : "Send a memory" }
    static var findMorePhotos: String { isCN ? "深挖更多这个人的照片" : "Find more photos of this person" }
    static var newFace: String { isCN ? "新人物" : "NEW FACE" }
    static var unsavedMemory: String { isCN ? "未保存的记忆" : "UNSAVED MEMORY" }
    static var added: String { isCN ? "已添加" : "ADDED" }
    static var someoneWorthRemembering: String { isCN ? "值得记住的人" : "Someone worth remembering" }
    static var viewInMemoryLane: String { isCN ? "在记忆空间中查看" : "View in memory lane" }
    static var addToMoreMemoryLanes: String { isCN ? "添加到更多记忆空间" : "Add to more memory lanes" }
    static var addToMemoryLane: String { isCN ? "添加到记忆空间" : "Add to memory lane" }
    static var faceNotRecognized: String { isCN ? "面部识别有误？" : "Face not correctly recognized?" }
    static var chooseMemoryLane: String { isCN ? "选择记忆空间" : "Choose a memory lane" }

    // MARK: Share Card
    static var timeCapsule: String { isCN ? "时光胶囊" : "Time Capsule" }
    static var excavation: String { isCN ? "出土证明" : "Excavation" }
    static var addALine: String { isCN ? "描述..." : "add a line..." }
    static var timeUnitYrs: String { isCN ? "年" : "yrs" }
    static var timeUnitMos: String { isCN ? "月" : "mos" }
    static var timeUnitDays: String { isCN ? "天" : "days" }
    static var timeUnitHrs: String { isCN ? "时" : "hrs" }
    static var timeUnitMin: String { isCN ? "分" : "min" }
    static var timeUnitSec: String { isCN ? "秒" : "sec" }
    static func yearsAgo(_ n: Int) -> String { isCN ? "\(n.formatted()) 年前" : "\(n.formatted()) year\(n == 1 ? "" : "s") ago" }
    static func monthsAgo(_ n: Int) -> String { isCN ? "\(n.formatted()) 个月前" : "\(n.formatted()) month\(n == 1 ? "" : "s") ago" }
    static func daysAgo(_ n: Int) -> String { isCN ? "\(n.formatted()) 天前" : "\(n.formatted()) day\(n == 1 ? "" : "s") ago" }
    static func hoursAgo(_ n: Int) -> String { isCN ? "\(n.formatted()) 小时前" : "\(n.formatted()) hour\(n == 1 ? "" : "s") ago" }
    static func minutesAgo(_ n: Int) -> String { isCN ? "\(n.formatted()) 分钟前" : "\(n.formatted()) minute\(n == 1 ? "" : "s") ago" }
    static func secondsAgo(_ n: Int) -> String { isCN ? "\(n.formatted()) 秒前" : "\(n.formatted()) second\(n == 1 ? "" : "s") ago" }
    static var yesterday: String { isCN ? "昨天" : "yesterday" }
    static var justNow: String { isCN ? "刚刚" : "just now" }
    static var aWhileAgo: String { isCN ? "很久以前" : "a while ago" }
    static func tunneledFrom(_ n: Int) -> String { isCN ? "从 \(n.formatted()) 张照片深处挖出" : "tunneled from \(n.formatted()) photos deep" }

    // MARK: Face Picker
    static var detectingFaces: String { isCN ? "正在识别面孔..." : "Detecting faces..." }
    static var whoIsThis: String { isCN ? "这是谁？" : "Who is this?" }
    static func addToNameMemoryLane(_ name: String) -> String { isCN ? "添加到\(name)的记忆空间" : "Add to \(name)'s memory lane" }
    static func alreadyInNameMemoryLane(_ name: String) -> String { isCN ? "已在\(name)的记忆空间中" : "Already in \(name)'s memory lane" }
    static var nameThisMemoryLane: String { isCN ? "为记忆空间命名" : "Name this memory lane" }
    static var creating: String { isCN ? "创建中..." : "Creating..." }
    static var createMemoryLane: String { isCN ? "创建记忆空间" : "Create memory lane" }
    static var addingPhoto: String { isCN ? "正在添加照片..." : "Adding photo..." }
    static var findMoreByScanning: String { isCN ? "扫描寻找更多照片" : "Find more photos by scanning" }
    static var backToCards: String { isCN ? "返回卡片" : "Back to cards" }

    // MARK: Memory Lane List
    static func shareInviteFor(_ name: String) -> String { isCN ? "分享\(name)的邀请链接" : "Share invite link for \(name)" }
    static var inviteNotSent: String { isCN ? "尚未发送邀请" : "Invite not sent yet" }
    static var couldntLoadMemoryLanes: String { isCN ? "无法加载记忆空间" : "Couldn't load memory lanes" }
    static var startYourFirst: String { isCN ? "开启你的第一个记忆空间" : "Start your first memory lane" }
    static var sendFirstMemory: String { isCN ? "分享第一段记忆" : "Send a first memory to someone\nyou want to stay close to." }
    static var inviteSomeone: String { isCN ? "邀请某人" : "Invite someone" }
    static var inviteLinkUnavailable: String { isCN ? "邀请链接不可用。请打开记忆空间生成链接。" : "Invite link unavailable.\nTry opening the memory lane to generate one." }
    static var findPeopleInPhotos: String { isCN ? "从照片中找人" : "Find people in photos" }
    static var shareInviteLink: String { isCN ? "分享邀请链接" : "Share invite link" }

    // MARK: Memory Lane Detail
    static var startThisMemoryLane: String { isCN ? "开启记忆空间" : "Start this memory lane" }
    static var addFirstMemoryBody: String { isCN ? "添加你的第一段记忆，照片、语音或简短的文字都行" : "Add your first memory.\nPhotos, voice clips, or just a few words." }
    static var photos: String { isCN ? "照片" : "Photos" }
    static func findPhotosOf(_ name: String) -> String { isCN ? "找\(name)的照片" : "Find photos of \(name)" }
    static var voiceClip: String { isCN ? "语音" : "Voice clip" }
    static var writeSomething: String { isCN ? "写点什么" : "Write something" }
    static func setFace(_ name: String) -> String { isCN ? "设置\(name)的面部" : "Set \(name)'s face" }
    static var senderYou: String { isCN ? "— 你" : "— You" }
    static func senderName(_ name: String) -> String { "— \(name)" }

    // MARK: Suggested Photos (Daily Dig)
    static func photosOf(_ name: String) -> String { isCN ? "\(name)的照片" : "Photos of \(name)" }
    static var noPhotosYet: String { isCN ? "还没找到照片" : "no photos found yet" }
    static var comeBackTomorrowDig: String { isCN ? "明天再来，隧道每天都都有新发现" : "come back tomorrow, the tunnel digs deeper each day" }
    static var comeBackMore: String { isCN ? "明天继续" : "come back tomorrow for more" }
    static var tunnelKeepsDigging: String { isCN ? "隧道还在继续挖" : "the tunnel keeps digging" }
    static func todaysDrop(_ n: Int) -> String { isCN ? "今日发现：\(n) 张新照片" : "today's drop: \(n) new" }
    static var noNewFinds: String { isCN ? "今天没有新发现" : "no new finds today" }
    static func tunneled(_ pct: Int) -> String { isCN ? "已挖掘 \(pct)%" : "\(pct)% tunneled" }
    static func totalPhotosFound(_ n: Int) -> String { isCN ? "累计找到 \(n) 张照片" : "\(n) total photos found across all sessions" }
    static var new: String { isCN ? "新" : "new" }
    static var deepScan: String { isCN ? "深度扫描" : "deep scan" }

    // MARK: Batch Photo Review
    static func photosSelected(_ n: Int) -> String { isCN ? "已选择 \(n) 张照片" : "\(n) photo\(n == 1 ? "" : "s") selected" }
    static var addDetailsToEach: String { isCN ? "为每张照片添加详情" : "Add details to each photo" }
    static var addAllDirectly: String { isCN ? "直接添加到记忆空间" : "Add all directly" }
    static var noPhotos: String { isCN ? "没有照片" : "No photos" }
    static func photoNOfTotal(_ n: Int, _ total: Int) -> String { isCN ? "第 \(n) 张，共 \(total) 张" : "Photo \(n) of \(total)" }
    static var addCaption: String { isCN ? "添加说明（可选）" : "Add a caption (optional)" }
    static var addAll: String { isCN ? "全部添加" : "Add all" }
    static func uploading(_ n: Int, _ total: Int) -> String { isCN ? "正在上传 \(n)/\(total)..." : "Uploading \(n)/\(total)..." }
    static func photosAdded(_ n: Int) -> String { isCN ? "已添加 \(n) 张照片" : "\(n) photo\(n == 1 ? "" : "s") added" }

    // MARK: Send Flow
    static var chooseAPhoto: String { isCN ? "选择一张照片" : "Choose a photo" }
    static var openPhotos: String { isCN ? "打开相册" : "Open Photos" }
    static var scanForSamePerson: String { isCN ? "扫描你的相册，找出同一个人的照片" : "Scans your photo library for photos\nwith the same person" }
    static var captionOptional: String { isCN ? "添加说明…（可选）" : "Add a caption… (optional)" }
    static var visibleTo: String { isCN ? "可见范围" : "Visible to" }
    static var visibility: String { isCN ? "可见性" : "Visibility" }
    static var thisMemoryOnly: String { isCN ? "仅此记忆" : "This memory only" }
    static var allMyMemories: String { isCN ? "我的全部记忆" : "All my memories" }
    static var sending: String { isCN ? "发送中…" : "Sending…" }
    static var sent: String { isCN ? "已发送" : "Sent" }
    static var inviteViaTap: String { isCN ? "如果对方还没有加入 Memory Tunnel，点击下方链接邀请" : "Tap the link below to invite them\nif they're not on Memory Tunnel yet." }
    static var somethingWentWrong: String { isCN ? "出了点问题" : "Something went wrong" }

    // MARK: Invite Flow
    static var theirNameHelps: String { isCN ? "他/她会证明记忆空间的意义" : "Their name helps you remember\nwhy this memory lane matters." }
    static var sendThemFirst: String { isCN ? "给对方发一段记忆" : "Send them a first memory" }
    static var photoThatMakesYouThink: String { isCN ? "一张让你想起他们的照片" : "A photo that makes you think of them." }
    static var sendAndInvite: String { isCN ? "发送并邀请" : "Send & invite" }
    static var creatingYourMemoryLane: String { isCN ? "正在创建记忆空间…" : "Creating your memory lane…" }
    static var memorySent: String { isCN ? "记忆已发送" : "Memory sent" }
    static var shareLinkToJoin: String { isCN ? "分享链接让对方加入你的记忆空间" : "Share the link so they can\njoin your memory lane." }

    // MARK: Voice Flow
    static var preview: String { isCN ? "预览" : "Preview" }
    static var soundsGood: String { isCN ? "听起来不错？" : "Sounds good?" }
    static var looksGoodContinue: String { isCN ? "不错——继续" : "Looks good — continue" }
    static var recordAgain: String { isCN ? "重新录制" : "Record again" }
    static var voiceClipSent: String { isCN ? "语音已发送" : "Voice clip sent" }
    static var comeBackTomorrowShort: String { isCN ? "明天继续" : "Come back tomorrow." }

    // MARK: Face Tagging
    static var whosInThisPhoto: String { isCN ? "这张照片里是谁？" : "Who's in this photo?" }
    static var helpsMTRemember: String { isCN ? "帮助 Memory Tunnel 下次认出他们" : "Helps Memory Tunnel remember them next time." }
    static func yesThat(_ name: String) -> String { isCN ? "是的，这是\(name)" : "Yes, that's \(name)" }

    // MARK: Face Confirmation
    static func whichFace(_ name: String) -> String { isCN ? "哪个是\(name)？" : "Which face is \(name)?" }
    static var helpsFindPhotos: String { isCN ? "这有助于在你的相册中找到他们的照片" : "This helps find their photos in your library" }
    static var currentFace: String { isCN ? "当前目标人物" : "Current face" }
    static var scanningMemoryLanePhotos: String { isCN ? "正在扫描记忆空间照片..." : "Scanning memory lane photos..." }
    static var noFacesInPhotos: String { isCN ? "记忆空间照片中未找到面孔。请先添加一些照片。" : "No faces found in memory lane photos.\nAdd some photos first." }
    static func faceSaved(_ name: String) -> String { isCN ? "已保存\(name)的面部" : "Face saved for \(name)" }
    static var appWillRecognize: String { isCN ? "我现在可以在你的整个相册中识别他们了" : "The app will now recognize them across your photo library" }

    // MARK: Memory Card
    static var tapToReload: String { isCN ? "点击重新加载" : "Tap to reload" }
    static var tapToRetry: String { isCN ? "点击重试" : "Tap to retry" }
    static var playing: String { isCN ? "播放中..." : "Playing..." }
    static var somewhere: String { isCN ? "某个地方" : "Somewhere" }

    // MARK: Metadata Fields
    static var whereWasThis: String { isCN ? "这是在哪里？" : "Where was this?" }
    static var addALocation: String { isCN ? "添加地点" : "Add a location" }
    static var whenWasThis: String { isCN ? "这是什么时候？" : "When was this?" }
    static var addADate: String { isCN ? "添加日期" : "Add a date" }
    static var howDoesThisFeel: String { isCN ? "这段记忆感觉如何？" : "How does this feel?" }

    // MARK: Edit / Compose / Record
    static var caption: String { isCN ? "说明" : "Caption" }
    static var deleteMemory: String { isCN ? "删除记忆" : "Delete memory" }
    static var editMemory: String { isCN ? "编辑记忆" : "Edit memory" }
    static var writeMemoryPlaceholder: String { isCN ? "写下一段记忆、想法或笔记..." : "Write a memory, thought, or note..." }
    static var addCaptionPlaceholder: String { isCN ? "添加说明..." : "Add a caption..." }
    static var discard: String { isCN ? "丢弃" : "Discard" }

    // MARK: On This Day
    static func atLocation(_ loc: String) -> String { isCN ? "在\(loc)" : "at \(loc)" }

    // MARK: Misc
    static var choosePhotosManually: String { isCN ? "手动选择照片" : "Choose photos manually" }
    static var createAnother: String { isCN ? "创建更多记忆空间" : "Create another memory lane" }
    static func photosWithName(_ name: String) -> String { isCN ? "与\(name)的照片" : "Photos with \(name.isEmpty ? "this person" : name)" }
    static var addMorePhotos: String { isCN ? "添加更多照片" : "Add more photos" }
    static var tapToChoosePhotos: String { isCN ? "点击选择照片" : "Tap to choose photos" }
    static var choosePhotos: String { isCN ? "选择照片" : "Choose photos for this memory lane" }
    static func selected(_ n: Int) -> String { isCN ? "已选 \(n) 张" : "\(n) selected" }
    static var chapterNameOptional: String { isCN ? "记忆空间名称（可选）" : "Memory lane name (optional)" }
    static var addDetails: String { isCN ? "添加详情" : "Add details" }
    static func chapterCreated() -> String { isCN ? "记忆空间已创建" : "Memory lane created" }
    static var createAnotherMemoryLane: String { isCN ? "再创建一个" : "Create another memory lane" }

    // MARK: Invited Landing
    static var couldntLoadInvitation: String { isCN ? "无法加载邀请" : "Couldn't load invitation" }
    static var skipToSignUp: String { isCN ? "跳过去注册" : "Skip to sign up" }
    static func invitedYou(_ name: String) -> String { isCN ? "\(name) 邀请了你" : "\(name) invited you" }
    static func toTheMemoryLane(_ name: String) -> String { isCN ? "加入记忆空间「\(name)」" : "to the memory lane \"\(name)\"" }
    static var youllCreateAccount: String { isCN ? "你将创建账号加入此记忆空间。" : "You'll create an account to join this memory lane." }
    static var joinAndAdd: String { isCN ? "加入并添加记忆" : "Join & Add Your Memories" }

    // MARK: Daily Card Warm Onramp
    static var warmOnrampTitle: String { isCN ? "你的记忆从分享第一张照片开始。" : "Your daily memories start\nwhen you share your first photo." }
}
