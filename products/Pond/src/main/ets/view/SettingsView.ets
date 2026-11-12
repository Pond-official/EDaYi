import { JwxtRepository } from '../data/JwxtRepository';
import { CacheManager } from '../data/CacheManager';
import { AppLog } from '../data/AppLog';
import { ReminderScheduler } from '../data/ReminderScheduler';
import { getContext } from '../net/JwTransport';
import { CloseButton } from './BackButton';
import { AppLogCard } from './AppLogCard';
import { FROST_BAND_HEIGHT, frostTopInsetVp } from './FrostBand';
import { SettingsCacheCard, SettingsPrivacyCard, SettingsReminderCard, SettingsSectionTitle } from './SettingsCards';
import { ExamAddCandidate, ExamCourseItem, SettingsExamAddEntry, SettingsExamAddList,
  SettingsExamEntry, SettingsExamListCard } from './SettingsExamCards';
import { FinalExamEntry, PlanCategory, PlanCourse, TermStatus } from '../model/JwModels';
import { ExamDateUtils } from '../utils/ExamDateUtils';
import { GITHUB_URL, SettingsAboutEntry, SettingsAcknowledgementCard, SettingsDeveloperCard,
  SettingsDeveloperEntry, SettingsDeveloperModeCard, SettingsOpenSourceCard, SettingsVersionCard } from './SettingsAboutCards';
import { bundleManager, common } from '@kit.AbilityKit';
import { pasteboard, BusinessError } from '@kit.BasicServicesKit';

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
  /** 当前二级页（经 AppStorage 与 Index 共享，Index onBackPress 处理设备侧滑/返回键时据此弹回主页） */
  @StorageLink('jwSettingsSubPage') subPage: SettingsSubPage = SettingsSubPage.Main;
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
  /** 版本号连续点击计数（开发者选项解锁用） */
  @State versionTapCount: number = 0;
  /** 自定义提前提醒时间输入弹层显隐 */
  @State showAdvanceSheet: boolean = false;
  /** 自定义提前分钟数输入内容（弹层内 TextInput） */
  @State advanceInputText: string = '';
  /** 添加科目弹层显隐（候选列表来自培养计划非考试课） */
  @State showExamAddSheet: boolean = false;
  /** 上次点击版本号的时间戳（毫秒），超过 3 秒视为不连续 */
  private lastVersionTapMs: number = 0;
  /** 解锁开发者选项需连续点击版本号的次数 */
  private static readonly DEVELOPER_UNLOCK_TAPS: number = 5;

  aboutToAppear(): void {
    AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'aboutToAppear');
    JwxtRepository.ensureLoaded();
    this.loadVersionName();
    this.refreshCacheSize();
  }

  aboutToDisappear(): void {
    AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'aboutToDisappear');
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
  }

  /** 二级页转场：从右侧滑入，退出时滑回右侧 */
  private subPageEnter(): TransitionEffect {
    return TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: '100%' }));
  }

  /** 主页转场：从左侧滑回，退出时向左滑出让位 */
  private mainPageEnter(): TransitionEffect {
    return TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: '-25%' }));
  }
}
