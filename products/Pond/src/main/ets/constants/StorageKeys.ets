/**
 * AppStorage / 卡片 LocalStorage 状态键契约清单（任务 11：状态键契约化）。
 *
 * 背景：@StorageProp / @StorageLink / @LocalStorageProp 的装饰器参数必须是字符串字面量
 * （传 const 常量编译不通过），因此状态键无法收口为常量，只能采用
 * 「本清单登记 + tools/check_storage_keys.mjs 校验」的方式契约化：
 * 新增/改名状态键必须同步本清单，否则校验脚本以非 0 退出码报错。
 *
 * 登记行格式（脚本按行首标记解析，请勿改动标记写法）：
 *   // [AppStorage] 键名 | 类型 | 写入方 | 读取方
 *   // [LocalStorage] 键名 | 类型 | 写入方 | 读取方
 *
 * 校验命令（项目根目录）：node tools/check_storage_keys.mjs
 */

// ================================ AppStorage 键（23 个） ================================

// [AppStorage] jwSafeTopPx | number | pondability/PondAbility（窗口避让安全高度） | pages/LoginIndex、pages/Index、pages/TrainingPlanIndex、view/FrostBand、view/GradeView、view/HomeView、view/SelectionView、view/SettingsView、view/ZcpView（9 处）
// [AppStorage] mainBreakpoint | string | common/utils/BreakpointSystem（pages/Index 注册，断点变化写入） | pages/TrainingPlanIndex、view/GradeView、view/HomeView、view/SelectionView、view/ZcpView（@StorageLink 5 处，双向）
// [AppStorage] jwDataMode | string（preview/online/offlineCache） | data/JwxtCacheStore、data/JwxtSessionRepository | pages/TrainingPlanIndex、view/GradeView、view/HomeView、view/ZcpView
// [AppStorage] jwStudent | model/JwModels.StudentProfile | data/JwxtCacheStore、data/JwxtSessionRepository（退出登录置空） | view/HomeView
// [AppStorage] jwSchedule | model/JwModels.ScheduleCellInfo[] | data/JwxtCacheStore、data/JwxtSessionRepository | view/HomeView、view/ScheduleBoard
// [AppStorage] jwTerm | model/JwModels.TermStatus | data/JwxtSessionRepository | view/HomeView、view/ScheduleBoard
// [AppStorage] jwGrades | model/JwModels.GradeEntry[] | data/JwxtCacheStore、data/JwxtSessionRepository | view/GradeView
// [AppStorage] jwGradeCategories | model/JwModels.GradeCategory[] | data/JwxtCacheStore、data/JwxtSessionRepository | view/GradeView
// [AppStorage] jwTrainingPlan | model/JwModels.PlanCategory[] | data/JwxtCacheStore、data/JwxtSessionRepository | pages/TrainingPlanIndex
// [AppStorage] jwFinalExams | model/JwModels.FinalExamEntry[] | data/JwxtRepository、data/JwxtSessionRepository、data/PrivacyController（严格模式清空） | view/HomeView、view/ScheduleBoard
// [AppStorage] jwForegroundTick | number | data/PrivacyController（隐私切换/清数据后通知回前台页刷新） | view/HomeView、view/ScheduleBoard、view/SelectionView
// [AppStorage] jwPrivacyMode | string（standard/strict） | data/JwxtSessionRepository、data/PrivacyController | view/HomeView（读）；view/SettingsView（@StorageLink，双向）
// [AppStorage] jwDeveloperMode | boolean | data/JwxtSessionRepository、data/PrivacyController | view/SettingsView（@StorageLink，双向）
// [AppStorage] jwReminderEnabled | boolean | data/JwxtSessionRepository | view/SettingsView（@StorageLink，双向）
// [AppStorage] jwReminderAdvance | number（分钟） | data/JwxtSessionRepository | view/SettingsView（@StorageLink，双向）
// [AppStorage] jwReminderAgentEnabled | boolean | data/JwxtSessionRepository | view/SettingsView（@StorageLink，双向）
// [AppStorage] jwNextReminder | string | data/JwxtSessionRepository、data/PrivacyController、data/ReminderScheduler | view/SettingsView
// [AppStorage] jwReminderDisabledSessions | string[]（课程序号） | data/JwxtSessionRepository、data/PrivacyController | view/ScheduleBoard
// [AppStorage] jwSettingsSubPage | view/SettingsView.SettingsSubPage | pages/SettingsIndex、view/SettingsView（@StorageLink 双向，跨页同步设置子页）
// [AppStorage] jwSelectionTabActive | boolean | pages/Index（页签切换时写入） | view/SelectionLoginPanel（选课页首次可见拉起验证码）
// [AppStorage] jwZcpTabActive | boolean | pages/Index（页签切换时写入） | view/ZcpView（综评页首次可见建立会话）
// [AppStorage] jwZcpResult | model/ZcpModels.ZcpResult | null | data/ZcpRepository、view/ZcpView（缓存回显/加载成功） | view/ZcpView
// [AppStorage] appLogRevision | number | data/AppLog（日志环形缓冲修订号） | view/AppLogCard

// ============================ 卡片 LocalStorage 键（15 个） ============================
// 均由 data/CardDataStore 构造 formData，经 formBindingData 注入对应卡片 @Entry(LocalStorage)；
// 刷新走 updateForm（卡片内 @Watch 监听 Json 字段变化重新解析）。

// [LocalStorage] weekText | string（"第N周"） | data/CardDataStore（课表卡片） | widget/pages/ScheduleCard、ScheduleCardLarge
// [LocalStorage] coursesJson | string（今日课程 JSON） | data/CardDataStore（课表卡片） | widget/pages/ScheduleCard
// [LocalStorage] moreText | string（"还有N门课"） | data/CardDataStore（课表卡片） | widget/pages/ScheduleCard
// [LocalStorage] emptyText | string（空态文案） | data/CardDataStore（课表/考试卡片） | widget/pages/ScheduleCard、ExamCountdownCard
// [LocalStorage] tomorrowJson | string（明日课程 JSON） | data/CardDataStore（课表卡片） | widget/pages/ScheduleCard
// [LocalStorage] tomorrowMoreText | string | data/CardDataStore（课表卡片） | widget/pages/ScheduleCard
// [LocalStorage] tomorrowEmptyText | string | data/CardDataStore（课表卡片） | widget/pages/ScheduleCard
// [LocalStorage] tomorrowWeekText | string | data/CardDataStore（课表卡片） | widget/pages/ScheduleCard
// [LocalStorage] weekCellsJson | string（周课表网格 JSON） | data/CardDataStore（课表大卡） | widget/pages/ScheduleCardLarge
// [LocalStorage] nextWeekCellsJson | string | data/CardDataStore（课表大卡） | widget/pages/ScheduleCardLarge
// [LocalStorage] nextWeekText | string | data/CardDataStore（课表大卡） | widget/pages/ScheduleCardLarge
// [LocalStorage] todayD | string（今日星期 1-7） | data/CardDataStore（课表大卡） | widget/pages/ScheduleCardLarge
// [LocalStorage] privacyDisabledText | string（严格隐私模式提示，非空即禁用卡片） | data/CardDataStore（全部卡片） | widget/pages/ScheduleCard、ScheduleCardLarge、ExamCountdownCard
// [LocalStorage] examsJson | string（考试列表 JSON） | data/CardDataStore（考试卡片） | widget/pages/ExamCountdownCard
// [LocalStorage] totalText | string（"共N场考试"） | data/CardDataStore（考试卡片） | widget/pages/ExamCountdownCard
