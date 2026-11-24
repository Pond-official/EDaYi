import { JwxtRepository } from '../data/JwxtRepository';
import { CacheManager } from '../data/CacheManager';
import { AppLog } from '../data/AppLog';
import { ReminderScheduler } from '../data/ReminderScheduler';
import { CardDataStore } from '../data/CardDataStore';
import { getContext } from '../net/JwTransport';
import { CloseButton } from './BackButton';
import { AppLogCard } from './AppLogCard';
import { FROST_BAND_HEIGHT, frostTopInsetVp } from './FrostBand';
import { SettingsCacheCard, SettingsBackgroundCard, SettingsCardNightCard, SettingsPrivacyCard, SettingsReminderCard, SettingsSectionTitle } from './SettingsCards';
import { ExamAddCandidate, ExamCourseItem, SettingsExamAddEntry, SettingsExamAddList,
  SettingsExamEntry, SettingsExamImportEntry, SettingsExamListCard, SettingsExamShareEntry } from './SettingsExamCards';
import { FinalExamEntry, PlanCategory, PlanCourse, TermStatus } from '../model/JwModels';
import { ExamDateUtils } from '../utils/ExamDateUtils';
import { ExamShareText } from '../utils/ExamShareText';
import { GITHUB_URL, SettingsAboutEntry, SettingsAcknowledgementCard, SettingsDeveloperCard,
  SettingsDeveloperEntry, SettingsDeveloperModeCard, SettingsOpenSourceCard, SettingsVersionCard } from './SettingsAboutCards';
import { SettingsLightEffectCard } from './SettingsLightEffectCards';
import { bundleManager, common } from '@kit.AbilityKit';
import { pasteboard, BusinessError } from '@kit.BasicServicesKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { systemShare, harmonyShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';

const SETTING_DOMAIN: number = 0x0000;
const SETTING_TAG: string = 'SettingsView';
/** 二级页推入/弹出转场时长（毫秒） */
export const PAGE_PUSH_DURATION: number = 380;

/** 设置二级页：主页 / 期末倒计时 / 开发者选项 / 关于应用 */
export enum SettingsSubPage {
  Main,
  ExamSchedule,
  Developer,
  About
}

/**
 * 设置页：上课提醒开关、隐私模式与存储管理（一级菜单），
 * 开发者选项（关于应用内连续点击版本号 5 次后显示）与关于应用（二级菜单）。
 * 提醒以系统通知（Notification Kit）发送，修改即时生效并持久化到 preferences。
 */
@Component
export struct SettingsView {
  @StorageLink('jwReminderEnabled') reminderEnabled: boolean = true;
  @StorageLink('jwReminderAdvance') reminderAdvance: number = 10;
  @StorageLink('jwReminderAgentEnabled') reminderAgentEnabled: boolean = true;
  @StorageProp('jwNextReminder') nextReminder: string = '';
  /** 当前二级页（经 AppStorage 与 Index 共享，Index onBackPress 处理设备侧滑/返回键时据此弹回主页；@Watch 联动碰一碰注册） */
  @StorageLink('jwSettingsSubPage') @Watch('onSubPageChanged') subPage: SettingsSubPage = SettingsSubPage.Main;
  /** 当前本地缓存大小文本 */
  @State cacheSizeText: string = '计算中…';
  /** 应用版本号 */
  @State versionText: string = '…';
  /** 本学期培养计划（期末倒计时二级页的考试课数据源） */
  @StorageProp('jwTrainingPlan') trainingPlan: PlanCategory[] = [];
  /** 当前学期（培养计划按 plannedTerm 与之匹配） */
  @StorageProp('jwTerm') termStatus: TermStatus = new TermStatus();
  /** 各课程期末考试时间设置（按课程名） */
  @StorageProp('jwFinalExams') finalExams: FinalExamEntry[] = [];
  /** 隐私模式：standard=缓存全部 / restricted=仅课表卡片 / strict=不缓存 */
  @StorageLink('jwPrivacyMode') privacyMode: string = 'standard';
  /** 状态栏避让区高度（px）：沉浸式全屏下内容顶部让位计算用 */
  @StorageProp('jwSafeTopPx') safeTopPx: number = 0;
  /** 开发者选项是否已开启（关于应用内连续点击版本号 5 次后开启） */
  @StorageLink('jwDeveloperMode') developerMode: boolean = false;
  /** 底栏光效颜色（开发者选项自定义，#RRGGBB） */
  @StorageLink('jwLightEffectColor') lightEffectColor: string = '#FFFFFF';
  /** 底栏材质档位（开发者选项自定义，ADAPTIVE/EXQUISITE/GENTLE/SMOOTH） */
  @StorageLink('jwMaterialLevel') materialLevel: string = 'ADAPTIVE';
  /** 2*4 课表小卡"晚间显示明日课程"开关 */
  @StorageLink('jwCardNightEnabled') cardNightEnabled: boolean = false;
  /** 每天开始默认展示明日课程的时刻（当日分钟数，默认 1200=20:00） */
  @StorageLink('jwCardNightMinutes') cardNightMinutes: number = 1200;
  /** 自定义背景图片沙箱路径（'' = 未导入） */
  @StorageLink('jwBackgroundUri') backgroundUri: string = '';
  /** 背景模式：system=跟随系统 / white=纯白 / image=自定义图片 */
  @StorageLink('jwBackgroundMode') backgroundMode: string = 'system';
  /** 版本号连续点击计数（开发者选项解锁用） */
  @State versionTapCount: number = 0;
  /** 自定义提前提醒时间输入弹层显隐 */
  @State showAdvanceSheet: boolean = false;
  /** 自定义提前分钟数输入内容（弹层内 TextInput） */
  @State advanceInputText: string = '';
  /** 添加科目弹层显隐（候选列表来自培养计划非考试课） */
  @State showExamAddSheet: boolean = false;
  /** 导入期末倒计时弹层显隐（长按粘贴分享文本，实时解析预览） */
  @State showExamImportSheet: boolean = false;
  /** 导入弹层输入内容（弹层内 TextArea，与「分享期末倒计时」发出的文本同格式） */
  @State examImportText: string = '';
  /** 上次点击版本号的时间戳（毫秒），超过 3 秒视为不连续 */
  private lastVersionTapMs: number = 0;
  /** 碰一碰/隔空传送是否已注册（期末倒计时页可见期间注册，防重复注册） */
  private deviceShareRegistered: boolean = false;
  /** 碰一碰/隔空传送事件回调（注册/注销复用同一引用） */
  private readonly deviceShareCallback: Callback<harmonyShare.SharableTarget> =
    (target: harmonyShare.SharableTarget): void => {
      this.onDeviceShare(target);
    };
  /** 解锁开发者选项需连续点击版本号的次数 */
  private static readonly DEVELOPER_UNLOCK_TAPS: number = 5;

  aboutToAppear(): void {
    AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'aboutToAppear');
    JwxtRepository.ensureLoaded();
    this.loadVersionName();
    this.refreshCacheSize();
    if (this.subPage === SettingsSubPage.ExamSchedule) {
      this.registerDeviceShare();
    }
  }

  aboutToDisappear(): void {
    AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'aboutToDisappear');
    this.unregisterDeviceShare();
  }

  /** 二级页切换：进入期末倒计时页注册碰一碰/隔空传送分享，离开时注销 */
  private onSubPageChanged(): void {
    if (this.subPage === SettingsSubPage.ExamSchedule) {
      this.registerDeviceShare();
    } else {
      this.unregisterDeviceShare();
    }
  }

  private applySettings(enabled: boolean, advanceMinutes: number, agentEnabled: boolean): void {
    JwxtRepository.updateReminderSettings(enabled, advanceMinutes, agentEnabled);
  }

  /** 打开自定义提前时间输入弹层，预填当前值 */
  private openAdvanceSheet(): void {
    this.advanceInputText = `${this.reminderAdvance}`;
    this.showAdvanceSheet = true;
  }

  /** 校验并应用自定义提前提醒分钟数（1-120 的整数） */
  private confirmAdvanceInput(): void {
    const minutes: number = Number(this.advanceInputText.trim());
    if (!Number.isInteger(minutes) || minutes < 1 || minutes > 120) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入 1-120 之间的整数分钟数' });
      return;
    }
    this.applySettings(this.reminderEnabled, minutes, this.reminderAgentEnabled);
    this.showAdvanceSheet = false;
  }

  /** 小卡"晚间显示明日课程"开始时间文案（当日分钟数转 HH:mm） */
  private cardNightTimeText(): string {
    const hours: number = Math.floor(this.cardNightMinutes / 60);
    const minutes: number = this.cardNightMinutes % 60;
    const hh: string = hours < 10 ? '0' + hours : `${hours}`;
    const mm: string = minutes < 10 ? '0' + minutes : `${minutes}`;
    return hh + ':' + mm;
  }

  /** 打开小卡晚间开始时间选择器（24 小时制，确认后写入设置并刷新桌面卡片） */
  private openCardNightTimePicker(): void {
    const selected: Date = new Date();
    selected.setHours(Math.floor(this.cardNightMinutes / 60), this.cardNightMinutes % 60, 0, 0);
    this.getUIContext().showTimePickerDialog({
      selected: selected,
      useMilitaryTime: true,
      onAccept: (time: TimePickerResult) => {
        JwxtRepository.updateCardNightSetting(this.cardNightEnabled, time.hour * 60 + time.minute);
      }
    });
  }

  /** 从系统图库选择自定义背景图片并导入应用沙箱（导入失败弹提示） */
  private async pickBackgroundImage(): Promise<void> {
    try {
      const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result: photoAccessHelper.PhotoSelectResult = await picker.select(options);
      if (result.photoUris.length === 0) {
        return;
      }
      const imported: string = JwxtRepository.applyBackgroundImage(result.photoUris[0]);
      if (imported === '') {
        this.getUIContext().getPromptAction().showToast({ message: '导入背景图片失败，请换一张试试' });
      }
    } catch (error) {
      AppLog.error(SETTING_DOMAIN, SETTING_TAG, 'pickBackgroundImage failed: %{public}s', `${error}`);
      this.getUIContext().getPromptAction().showToast({ message: '打开图库失败' });
    }
  }

  /** 切换背景模式：选中"自定义图片"且尚未导入过图片时仅拉起图库，导入成功后才切入 image 模式（取消/失败则模式不变） */
  private selectBackgroundMode(mode: string): void {
    if (mode === 'image' && this.backgroundUri === '') {
      this.pickBackgroundImage();
      return;
    }
    JwxtRepository.updateBackgroundMode(mode);
  }

  /** 重新统计本地缓存大小并刷新显示 */
  private refreshCacheSize(): void {
    this.cacheSizeText = CacheManager.formatSize(JwxtRepository.getCacheSizeBytes());
  }

  /** 弹窗确认后清理本地缓存 */
  private confirmClearCache(): void {
    this.getUIContext().showAlertDialog({
      title: '清理缓存',
      message: '将清理本地缓存数据（网页缓存与课表、成绩等离线缓存），不影响已添加的桌面卡片和登录状态。确定清理吗？',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '清理',
        fontColor: Color.Red,
        action: () => {
          JwxtRepository.clearLocalCaches();
          this.refreshCacheSize();
        }
      }
    });
  }

  /** 读取本应用版本号 */
  private loadVersionName(): void {
    bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      .then((info: bundleManager.BundleInfo) => {
        this.versionText = info.versionName;
      })
      .catch((error: BusinessError) => {
        AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'getBundleInfo failed: %{public}s', JSON.stringify(error));
        this.versionText = '未知';
      });
  }

  /** 版本号点击：未开启时连续点击 5 次开启开发者选项；已开启时连续点击提示已开启（均防误触） */
  private onVersionTap(): void {
    const now: number = Date.now();
    if (now - this.lastVersionTapMs > 3000) {
      this.versionTapCount = 0;
    }
    this.lastVersionTapMs = now;
    this.versionTapCount += 1;
    if (this.developerMode) {
      // 已开启：首次点击不提示，防止误触；第二次起提示已开启
      if (this.versionTapCount >= 2) {
        this.getUIContext().getPromptAction().showToast({ message: '开发者选项已开启' });
        AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'developer mode already enabled');
      }
      return;
    }
    if (this.versionTapCount >= SettingsView.DEVELOPER_UNLOCK_TAPS) {
      this.versionTapCount = 0;
      JwxtRepository.updateDeveloperMode(true);
      this.getUIContext().getPromptAction().showToast({ message: '开发者选项已开启' });
      AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'developer mode unlocked');
      return;
    }
    if (this.versionTapCount >= 2) {
      // 首次点击不提示，防止误触；第二次起提示剩余次数
      const remain: number = SettingsView.DEVELOPER_UNLOCK_TAPS - this.versionTapCount;
      this.getUIContext().getPromptAction().showToast({ message: `再按 ${remain} 次开启开发者选项` });
    }
  }

  /** 复制 GitHub 开源地址 */
  private copyGithubUrl(): void {
    const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, GITHUB_URL);
    pasteboard.getSystemPasteboard().setData(data)
      .then(() => {
        this.getUIContext().getPromptAction().showToast({ message: '链接已复制' });
      })
      .catch((error: BusinessError) => {
        AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'copy url failed: %{public}s', JSON.stringify(error));
      });
  }

  /** 点击开源地址：先弹窗确认，确认后使用默认浏览器打开 */
  private openGithubUrl(): void {
    this.getUIContext().showAlertDialog({
      title: '访问开源地址',
      message: '即将打开浏览器访问\n' + GITHUB_URL + '\n是否继续？',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '访问',
        action: () => {
          this.jumpToGithub();
        }
      }
    });
  }

  /** 使用默认浏览器打开 GitHub 开源地址 */
  private jumpToGithub(): void {
    const context: common.UIAbilityContext | null = JwxtRepository.getUiAbilityContext();
    if (context === null) {
      return;
    }
    context.openLink(GITHUB_URL, { appLinkingOnly: false })
      .catch((error: BusinessError) => {
        AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'open url failed: %{public}s', JSON.stringify(error));
        this.getUIContext().getPromptAction().showToast({ message: '打开链接失败' });
      });
  }

  /** 选择隐私模式：严格模式弹窗警告，确认后才生效 */
  private selectPrivacyMode(mode: string): void {
    if (mode === this.privacyMode) {
      return;
    }
    if (mode === 'strict') {
      this.getUIContext().showAlertDialog({
        title: '严格隐私模式',
        message: '开启后将不会缓存任何教务信息，桌面卡片将无法使用；应用进入后台运行或退出后，将自动清理缓存并退出登录，下次使用需重新登录。确定开启吗？',
        primaryButton: {
          value: '取消',
          action: () => {
          }
        },
        secondaryButton: {
          value: '开启',
          fontColor: $r('sys.color.ohos_id_color_warning'),
          action: () => {
            JwxtRepository.updatePrivacyMode('strict');
          }
        }
      });
      return;
    }
    JwxtRepository.updatePrivacyMode(mode);
  }

  /** 该课程已设的期末考试时间（未设置返回空串） */
  private examDateOfCourse(courseName: string): string {
    const found: FinalExamEntry | undefined = this.finalExams
      .find((e: FinalExamEntry): boolean => e.courseName === courseName);
    return found !== undefined ? found.examDate : '';
  }

  /**
   * 期末倒计时考试课列表：本学期培养计划中考核方式为"考试"的课程（去重），
   * 追加已设置时间但不在上述列表的课程（便于查看与清除），
   * 已设时间的课程排前面并按考试时间升序，未设置的保持计划顺序在后。
   */
  private examCourseItems(): ExamCourseItem[] {
    const items: ExamCourseItem[] = [];
    const seen: string[] = [];
    const termCode: string = this.termStatus.termCode;
    for (const category of this.trainingPlan) {
      for (const course of category.courses) {
        if (course.examTypeText !== '考试' || course.plannedTerm !== termCode) {
          continue;
        }
        if (seen.indexOf(course.courseName) >= 0) {
          continue;
        }
        seen.push(course.courseName);
        const item: ExamCourseItem = new ExamCourseItem();
        item.courseName = course.courseName;
        item.subtitle = course.credit + '学分 · ' + course.natureText;
        item.examDate = this.examDateOfCourse(course.courseName);
        items.push(item);
      }
    }
    for (const entry of this.finalExams) {
      if (seen.indexOf(entry.courseName) >= 0) {
        continue;
      }
      seen.push(entry.courseName);
      const item: ExamCourseItem = new ExamCourseItem();
      item.courseName = entry.courseName;
      const planCourse: PlanCourse | null = this.planCourseOf(entry.courseName);
      if (planCourse !== null) {
        item.subtitle = planCourse.credit + '学分 · ' + planCourse.natureText
          + ' · ' + planCourse.examTypeText;
      } else {
        item.subtitle = '不在本学期培养计划考试课中';
      }
      item.examDate = entry.examDate;
      items.push(item);
    }
    items.sort((a: ExamCourseItem, b: ExamCourseItem): number => {
      const aSet: boolean = a.examDate.length > 0;
      const bSet: boolean = b.examDate.length > 0;
      if (aSet !== bSet) {
        return aSet ? -1 : 1;
      }
      if (aSet) {
        return a.examDate < b.examDate ? -1 : (a.examDate > b.examDate ? 1 : 0);
      }
      return 0;
    });
    return items;
  }

  /** 考试课列表空态文案：按数据来源区分引导 */
  private examEmptyText(): string {
    if (this.trainingPlan.length === 0) {
      return '登录教务系统后同步培养计划，本学期考试课将显示在这里';
    }
    if (this.termStatus.termCode.length === 0) {
      return '暂无法确定当前学期，登录教务系统后显示本学期考试课';
    }
    return '本学期培养计划中没有考核方式为"考试"的课程';
  }

  /** 点击考试课：先选日期再选时间（精确到分钟），确认后写入期末倒计时 */
  private openExamPicker(item: ExamCourseItem): void {
    this.openExamPickerFor(item.courseName, item.examDate);
  }

  /** 按课程名打开日期+时间选择器（精确到分钟），确认后写入期末倒计时 */
  private openExamPickerFor(courseName: string, currentExamDate: string): void {
    const current: Date | null =
      currentExamDate.length > 0 ? ExamDateUtils.parseExamDate(currentExamDate) : null;
    this.getUIContext().showDatePickerDialog({
      selected: current ?? new Date(),
      onDateAccept: (value: Date) => {
        this.getUIContext().showTimePickerDialog({
          selected: current ?? new Date(),
          useMilitaryTime: true,
          onAccept: (time: TimePickerResult) => {
            JwxtRepository.updateFinalExam(courseName,
              ExamDateUtils.toMinuteText(value, time.hour, time.minute));
          }
        });
      }
    });
  }

  /** 清除单门课程的期末考试时间 */
  private clearExamTime(item: ExamCourseItem): void {
    JwxtRepository.updateFinalExam(item.courseName, '');
  }

  /** 导入弹层：当前输入文本解析出的待导入条目（与分享文本共用同一解析） */
  private parsedImportEntries(): FinalExamEntry[] {
    return ExamShareText.parse(this.examImportText);
  }

  /** 导入弹层单条倒计时文本（时间非法显示"时间无效"） */
  private importCountdownOf(entry: FinalExamEntry): string {
    const parsed: Date | null = ExamDateUtils.parseExamDate(entry.examDate);
    return parsed !== null ? ExamDateUtils.countdownTextOf(parsed) : '时间无效';
  }

  /** 确认导入：解析输入文本，按课程名合并到本机期末倒计时（与分享面板导入同一链路） */
  private confirmExamImport(): void {
    const entries: FinalExamEntry[] = this.parsedImportEntries();
    if (entries.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '没有可导入的考试时间' });
      return;
    }
    const context: common.UIAbilityContext | null = getContext();
    if (context === null) {
      this.getUIContext().getPromptAction().showToast({ message: '导入失败，请重试' });
      return;
    }
    const changed: number = CardDataStore.importFinalExams(context, entries);
    AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'exam import done, changed: %{public}d', `${changed}`);
    this.showExamImportSheet = false;
    this.getUIContext().getPromptAction().showToast({ message: '已导入 ' + changed + ' 门考试时间' });
  }

  /** 已设考试时间的条目（按考试时间升序），供分享/碰一碰发送共用 */
  private sortedExamEntries(): FinalExamEntry[] {
    return this.finalExams
      .filter((entry: FinalExamEntry): boolean => entry.examDate.length > 0)
      .sort((a: FinalExamEntry, b: FinalExamEntry): number =>
        a.examDate < b.examDate ? -1 : (a.examDate > b.examDate ? 1 : 0));
  }

  /**
   * 分享期末倒计时：已设考试时间按时间升序拼为可读文本（ExamShareText，与导入解析共用格式），
   * 经系统分享面板（Share Kit）发送到其他设备或应用（华为分享/信息等渠道）。
   */
  private shareExamSchedule(): void {
    const entries: FinalExamEntry[] = this.sortedExamEntries();
    if (entries.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '暂无可分享的考试时间' });
      return;
    }
    const context: common.UIAbilityContext | null = JwxtRepository.getUiAbilityContext();
    if (context === null) {
      this.getUIContext().getPromptAction().showToast({ message: '分享失败' });
      return;
    }
    try {
      const data: systemShare.SharedData = new systemShare.SharedData({
        utd: utd.UniformDataType.PLAIN_TEXT,
        title: '期末倒计时',
        content: ExamShareText.buildShareText(entries)
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(data);
      controller.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE
      })
        .catch((error: BusinessError) => {
          AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'share exam schedule failed: %{public}s', JSON.stringify(error));
          this.getUIContext().getPromptAction().showToast({ message: '分享失败' });
        });
    } catch (error) {
      AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'share exam schedule threw: %{public}s', `${error}`);
      this.getUIContext().getPromptAction().showToast({ message: '分享失败' });
    }
  }

  /** 注册碰一碰与隔空传送分享（设备支持且尚未注册时）：期末倒计时页可见期间可经华为分享发送已设考试时间 */
  private registerDeviceShare(): void {
    if (this.deviceShareRegistered || !canIUse('SystemCapability.Collaboration.HarmonyShare')) {
      return;
    }
    let registered: boolean = false;
    try {
      harmonyShare.on('knockShare', this.deviceShareCallback);
      registered = true;
      AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'knockShare registered');
    } catch (error) {
      AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'knockShare register failed: %{public}s', `${error}`);
    }
    try {
      harmonyShare.on('gesturesShare', this.deviceShareCallback);
      registered = true;
      AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'gesturesShare registered');
    } catch (error) {
      AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'gesturesShare register failed: %{public}s', `${error}`);
    }
    this.deviceShareRegistered = registered;
  }

  /** 注销碰一碰与隔空传送分享 */
  private unregisterDeviceShare(): void {
    if (!this.deviceShareRegistered) {
      return;
    }
    this.deviceShareRegistered = false;
    try {
      harmonyShare.off('knockShare', this.deviceShareCallback);
      AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'knockShare unregistered');
    } catch (error) {
      AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'knockShare off failed: %{public}s', `${error}`);
    }
    try {
      harmonyShare.off('gesturesShare', this.deviceShareCallback);
      AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'gesturesShare unregistered');
    } catch (error) {
      AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'gesturesShare off failed: %{public}s', `${error}`);
    }
  }

  /**
   * 碰一碰/隔空传送触发（harmonyShare knockShare/gesturesShare 回调）：
   * 按「分享期末倒计时」同一格式经华为分享发送，对端设备接收后经导入页自动合并到本机期末倒计时；
   * 无已设考试时间时以 NO_CONTENT_ERROR 拒绝。
   */
  private onDeviceShare(target: harmonyShare.SharableTarget): void {
    const entries: FinalExamEntry[] = this.sortedExamEntries();
    if (entries.length === 0) {
      target.reject(harmonyShare.SharableErrorCode.NO_CONTENT_ERROR)
        .catch((error: BusinessError) => {
          AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'deviceShare reject failed: %{public}s', JSON.stringify(error));
        });
      return;
    }
    try {
      const data: systemShare.SharedData = new systemShare.SharedData({
        utd: utd.UniformDataType.PLAIN_TEXT,
        title: '期末倒计时',
        content: ExamShareText.buildShareText(entries)
      });
      target.share(data)
        .catch((error: BusinessError) => {
          AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'deviceShare send failed: %{public}s', JSON.stringify(error));
        });
      AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'deviceShare sent, entries: %{public}d', `${entries.length}`);
    } catch (error) {
      AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'deviceShare build data threw: %{public}s', `${error}`);
    }
  }

  /** 培养计划本学期课程查询（按课程名），未找到返回 null */
  private planCourseOf(courseName: string): PlanCourse | null {
    const termCode: string = this.termStatus.termCode;
    for (const category of this.trainingPlan) {
      for (const course of category.courses) {
        if (course.courseName === courseName && course.plannedTerm === termCode) {
          return course;
        }
      }
    }
    return null;
  }

  /** 添加科目候选列表：本学期培养计划中考核方式非"考试"的课程，排除已在列表中的科目 */
  private examAddCandidates(): ExamAddCandidate[] {
    const excluded: string[] = [];
    for (const item of this.examCourseItems()) {
      excluded.push(item.courseName);
    }
    const candidates: ExamAddCandidate[] = [];
    const seen: string[] = [];
    const termCode: string = this.termStatus.termCode;
    for (const category of this.trainingPlan) {
      for (const course of category.courses) {
        if (course.plannedTerm !== termCode || course.examTypeText === '考试') {
          continue;
        }
        if (excluded.indexOf(course.courseName) >= 0 || seen.indexOf(course.courseName) >= 0) {
          continue;
        }
        seen.push(course.courseName);
        const candidate: ExamAddCandidate = new ExamAddCandidate();
        candidate.courseName = course.courseName;
        candidate.subtitle = course.credit + '学分 · ' + course.natureText
          + ' · ' + course.examTypeText;
        candidates.push(candidate);
      }
    }
    return candidates;
  }

  /** 添加科目候选列表空态文案：按数据来源区分引导 */
  private examAddEmptyText(): string {
    if (this.trainingPlan.length === 0) {
      return '登录教务系统后同步培养计划，可从中添加科目';
    }
    if (this.termStatus.termCode.length === 0) {
      return '暂无法确定当前学期，登录教务系统后可添加科目';
    }
    return '本学期培养计划中已没有其他可添加的科目';
  }

  /** 自定义提前提醒时间输入弹层内容（体内直读状态，随输入刷新；弹层经页面根节点 bindSheet 挂载） */
  @Builder
  advanceSheetContent() {
    Column({ space: 16 }) {
      Text('自定义提前提醒时间')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .width('100%')
      Text('输入上课前多少分钟提醒，可设 1-120 分钟')
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .width('100%')
      TextInput({ text: this.advanceInputText, placeholder: '1-120' })
        .type(InputType.Number)
        .fontSize(16)
        .maxLength(3)
        .width('100%')
        .onChange((value: string) => {
          this.advanceInputText = value;
        })
        .enterKeyType(EnterKeyType.Done)
        .onSubmit(() => {
          this.confirmAdvanceInput();
        })
      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .onClick(() => {
            this.showAdvanceSheet = false;
          })
        Button('确定')
          .layoutWeight(1)
          .onClick(() => {
            this.confirmAdvanceInput();
          })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 28, right: 28, top: 12, bottom: 36 })
  }

  /** 添加科目弹层内容：培养计划非考试课候选列表（点击科目进入日期+时间选择器） */
  @Builder
  examAddSheetContent() {
    Column() {
      Row() {
        Text('添加科目')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
        Blank()
        CloseButton({
          onClose: (): void => {
            this.showExamAddSheet = false;
          }
        })
      }
      .width('100%')

      Text('从本学期培养计划中选择考查课等非考试科目，设置其考试时间')
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .width('100%')
        .margin({ top: 4 })
      Scroll() {
        SettingsExamAddList({
          candidates: this.examAddCandidates(),
          emptyText: this.examAddEmptyText(),
          onPick: (candidate: ExamAddCandidate): void => {
            this.showExamAddSheet = false;
            this.openExamPickerFor(candidate.courseName, '');
          }
        })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 28, right: 28, top: 12, bottom: 24 })
  }

  /** 导入期末倒计时弹层内容：长按粘贴分享文本，实时解析预览，确认后按课程名合并导入 */
  @Builder
  examImportSheetContent() {
    Column({ space: 16 }) {
      Text('导入期末倒计时')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .width('100%')
      Text('长按下方输入框粘贴分享文本，识别「课程名：YYYY-MM-DD HH:mm」格式的考试时间')
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .width('100%')
      TextArea({ text: this.examImportText, placeholder: '长按粘贴「分享期末倒计时」发出的文本' })
        .fontSize(14)
        .height(110)
        .width('100%')
        .onChange((value: string) => {
          this.examImportText = value;
        })
      if (this.parsedImportEntries().length > 0) {
        Text('识别到 ' + this.parsedImportEntries().length + ' 门考试时间，导入后按课程名合并到本机设置')
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .width('100%')
        Scroll() {
          Column() {
            ForEach(this.parsedImportEntries(), (entry: FinalExamEntry) => {
              Row() {
                Column({ space: 2 }) {
                  Text(entry.courseName)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('sys.color.ohos_id_color_text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(ExamDateUtils.formatDisplay(entry.examDate))
                    .fontSize(11)
                    .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                    .maxLines(1)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Text(this.importCountdownOf(entry))
                  .fontSize(12)
                  .fontColor($r('sys.color.ohos_id_color_text_primary_activated'))
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .padding({ top: 8, bottom: 8 })
            }, (entry: FinalExamEntry) => 'examImport' + entry.courseName + ':' + entry.examDate)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .align(Alignment.Start)
        .constraintSize({ maxHeight: 220 })
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
      }
      if (this.privacyMode === 'strict') {
        Text('当前隐私模式不缓存教务数据，导入结果不会保留到本地')
          .fontSize(11)
          .fontColor($r('sys.color.ohos_id_color_warning'))
          .width('100%')
      }
      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .onClick(() => {
            this.showExamImportSheet = false;
          })
        Button('导入')
          .layoutWeight(1)
          .enabled(this.parsedImportEntries().length > 0)
          .onClick(() => {
            this.confirmExamImport();
          })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 28, right: 28, top: 12, bottom: 36 })
  }

  build() {
    Column() {
      if (this.subPage === SettingsSubPage.ExamSchedule) {
        // 「期末倒计时」标题悬浮于顶带返回键旁（由 SettingsIndex 渲染），此处不重复
        Scroll() {
          Column() {
            SettingsExamListCard({
              items: this.examCourseItems(),
              emptyText: this.examEmptyText(),
              onPick: (item: ExamCourseItem): void => {
                this.openExamPicker(item);
              },
              onClear: (item: ExamCourseItem): void => {
                this.clearExamTime(item);
              }
            })
            SettingsExamAddEntry((): void => {
              this.showExamAddSheet = true;
            })
            SettingsExamShareEntry((): void => {
              this.shareExamSchedule();
            })
            SettingsExamImportEntry((): void => {
              AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'open exam import sheet');
              this.showExamImportSheet = true;
            })
            if (canIUse('SystemCapability.Collaboration.HarmonyShare')) {
              Text('支持碰一碰与隔空传送：两部手机亮屏解锁并开启华为分享，在本页顶部轻碰（或握拳抓握隔空传送）即可发送已设考试时间，对端接收后自动导入。')
                .fontSize(11)
                .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                .width('100%')
                .padding({ left: 4, right: 4, top: 8 })
            }
            Text('考试课来自本学期培养计划（考核方式为"考试"）；点击科目设置考试日期与时间，到点后自动移除；考查课等非考试科目可点"添加科目"从培养计划中选择。')
              .fontSize(11)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .width('100%')
              .padding({ left: 4, right: 4, top: 8 })
          }
          .padding({ left: 16, right: 16, top: frostTopInsetVp(this.safeTopPx, this.getUIContext()), bottom: 88 })
          .constraintSize({ minWidth: '100%', minHeight: '100%' })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .transition(this.subPageEnter())
      } else if (this.subPage === SettingsSubPage.Developer) {
        // 「开发者选项」标题悬浮于顶带返回键旁（由 SettingsIndex 渲染），此处不重复
        Scroll() {
          Column({ space: 16 }) {
            SettingsDeveloperModeCard({
              developerMode: this.developerMode,
              onModeToggle: (isOn: boolean): void => {
                if (isOn === this.developerMode) {
                  return;
                }
                AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'developer mode toggled: %{public}s', `${isOn}`);
                JwxtRepository.updateDeveloperMode(isOn);
                if (!isOn) {
                  this.getUIContext().animateTo({ duration: PAGE_PUSH_DURATION, curve: Curve.Friction }, () => {
                    this.subPage = SettingsSubPage.Main;
                  });
                }
              }
            })
            SettingsDeveloperCard(() => {
              ReminderScheduler.publishTest(getContext());
            })
            SettingsLightEffectCard({
              color: this.lightEffectColor,
              level: this.materialLevel,
              onColorPick: (color: string): void => {
                JwxtRepository.updateLightEffectSettings(color, this.materialLevel);
              },
              onLevelPick: (level: string): void => {
                JwxtRepository.updateLightEffectSettings(this.lightEffectColor, level);
              }
            })
            AppLogCard()
          }
          .padding({ left: 16, right: 16, top: frostTopInsetVp(this.safeTopPx, this.getUIContext()), bottom: 88 })
          .constraintSize({ minWidth: '100%', minHeight: '100%' })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .transition(this.subPageEnter())
      } else if (this.subPage === SettingsSubPage.About) {
        // 「关于应用」标题悬浮于顶带返回键旁（由 SettingsIndex 渲染），此处不重复
        Scroll() {
          Column() {
            SettingsVersionCard({
              versionText: this.versionText,
              onVersionTap: (): void => {
                this.onVersionTap();
              }
            })
            SettingsOpenSourceCard(() => {
              this.openGithubUrl();
            }, () => {
              this.copyGithubUrl();
            })
            SettingsAcknowledgementCard()
          }
          .padding({ left: 16, right: 16, top: frostTopInsetVp(this.safeTopPx, this.getUIContext()), bottom: 88 })
          .constraintSize({ minWidth: '100%', minHeight: '100%' })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .transition(this.subPageEnter())
      } else {
        Scroll() {
          Column() {
            // 「设置」标题悬浮于顶带返回键旁（由 SettingsIndex 渲染），此处不重复
            SettingsReminderCard({
              reminderEnabled: this.reminderEnabled,
              nextReminder: this.nextReminder,
              reminderAdvance: this.reminderAdvance,
              reminderAgentEnabled: this.reminderAgentEnabled,
              onToggleReminder: (isOn: boolean): void => {
                this.applySettings(isOn, this.reminderAdvance, this.reminderAgentEnabled);
              },
              onSelectAdvance: (minutes: number): void => {
                if (this.reminderAdvance !== minutes) {
                  this.applySettings(this.reminderEnabled, minutes, this.reminderAgentEnabled);
                }
              },
              onOpenAdvanceSheet: (): void => {
                this.openAdvanceSheet();
              },
              onToggleAgent: (isOn: boolean): void => {
                this.applySettings(this.reminderEnabled, this.reminderAdvance, isOn);
              }
            })
            SettingsExamEntry(() => {
              AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'enterExamPage clicked');
              this.getUIContext().animateTo({ duration: PAGE_PUSH_DURATION, curve: Curve.Friction }, () => {
                this.subPage = SettingsSubPage.ExamSchedule;
              });
            })
            SettingsSectionTitle('桌面卡片')
            SettingsCardNightCard({
              enabled: this.cardNightEnabled,
              timeText: this.cardNightTimeText(),
              onToggle: (isOn: boolean): void => {
                JwxtRepository.updateCardNightSetting(isOn, this.cardNightMinutes);
              },
              onPickTime: (): void => {
                this.openCardNightTimePicker();
              }
            })
            SettingsSectionTitle('个性化')
            SettingsBackgroundCard({
              backgroundMode: this.backgroundMode,
              backgroundUri: this.backgroundUri,
              onSelectMode: (mode: string): void => {
                this.selectBackgroundMode(mode);
              },
              onPick: (): void => {
                this.pickBackgroundImage();
              }
            })
            SettingsSectionTitle('隐私')
            SettingsPrivacyCard({
              privacyMode: this.privacyMode,
              onSelect: (value: string): void => {
                this.selectPrivacyMode(value);
              }
            })
            SettingsSectionTitle('存储')
            SettingsCacheCard({
              cacheSizeText: this.cacheSizeText,
              onClearCache: (): void => {
                this.confirmClearCache();
              }
            })
            if (this.developerMode) {
              SettingsSectionTitle('开发者选项')
              SettingsDeveloperEntry(() => {
                AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'enterDeveloperPage clicked');
                this.getUIContext().animateTo({ duration: PAGE_PUSH_DURATION, curve: Curve.Friction }, () => {
                  this.subPage = SettingsSubPage.Developer;
                });
              })
            }
            SettingsSectionTitle('关于')
            SettingsAboutEntry(() => {
              AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'enterAboutPage clicked');
              this.getUIContext().animateTo({ duration: PAGE_PUSH_DURATION, curve: Curve.Friction }, () => {
                this.subPage = SettingsSubPage.About;
              })
            })
          }
          .padding({ left: 16, right: 16, top: frostTopInsetVp(this.safeTopPx, this.getUIContext()), bottom: 88 })
          .constraintSize({ minWidth: '100%', minHeight: '100%' })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .transition(this.mainPageEnter())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .bindSheet($$this.showAdvanceSheet, this.advanceSheetContent(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: true
    })
    .bindSheet($$this.showExamAddSheet, this.examAddSheetContent(), {
      height: '80%',
      width: '55%',
      dragBar: true,
      showClose: false,
      enableOutsideInteractive: false,
      shouldDismiss: (sheetDismiss: SheetDismiss): void => {
        sheetDismiss.dismiss();
      }
    })
    .bindSheet($$this.showExamImportSheet, this.examImportSheetContent(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: true
    })
  }

  /** 二级页转场：从右侧滑入并淡入，退出时滑回右侧并淡出 */
  private subPageEnter(): TransitionEffect {
    return TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: '100%' }))
      .animation({ duration: 300, curve: Curve.EaseOut });
  }

  /** 主页转场：从左侧滑回并淡入，退出时向左滑出让位并淡出 */
  private mainPageEnter(): TransitionEffect {
    return TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: '-25%' }))
      .animation({ duration: 300, curve: Curve.EaseOut });
  }
}
