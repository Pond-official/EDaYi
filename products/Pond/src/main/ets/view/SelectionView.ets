import { display, window } from '@kit.ArkUI';
import { CourseListResult, SelectionBatch, SelectionCourse, SelectionOutcome, SelectedCourse } from '../model/SelectionModels';
import { SelectionRepository, SESSION_INVALID_ERROR } from '../data/SelectionRepository';
import { FrostBand, frostTopInsetVp } from './FrostBand';
import { SelectionLoginPanel } from './SelectionLoginPanel';
import {
  SelectionBatchSection, SelectionCourseCard, SelectionCoursesEmptyCard, SelectionCoursesLoadingCard,
  SelectionHeaderCard, SelectionLoadMoreRow, SelectionSearchRow, SelectionSelectedCard, SelectionTipCard,
  batchStatus, loginSummaryText, plainError, totalCourseText
} from './SelectionCards';

/** 课程列表每页条数（接口 pageSize） */
const PAGE_SIZE: number = 10;

/**
 * 选课页：选课系统（jwxk.dmu.edu.cn）为独立账号体系，
 * 原生登录（学号 + 密码 + 图形验证码，密码按服务端要求 AES-128-ECB 加密提交），
 * 登录后在线获取轮次、可选课程、已选课程并提交选课；
 * 登录凭证仅保留在内存，不缓存任何选课数据；
 * 提交选课（clazz/add）为异步入队且服务端要求绝不重试，仅提交一次后回查已选列表确认。
 */
@Component
export struct SelectionView {
  @StorageLink('mainBreakpoint') currentBreakpoint: string = 'md';
  @StorageProp('jwForegroundTick') @Watch('onForegroundTick') foregroundTick: number = 0;
  /** 是否已登录选课系统（凭证仅内存态，冷启动后为 false） */
  @State loggedIn: boolean = false;
  /** 回到登录页的重置信号：递增触发 SelectionLoginPanel 重置提示并换新验证码 */
  @State loginResetTick: number = 0;
  /** 回到登录页时要展示的提示（会话过期原因等，空串不覆盖） */
  @State loginResetMessage: string = '';
  @State studentNameText: string = '';
  @State batches: SelectionBatch[] = [];
  @State currentBatchIndex: number = 0;
  @State selectedCourses: SelectedCourse[] = [];
  @State courses: SelectionCourse[] = [];
  @State totalCourses: number = 0;
  @State pageNumber: number = 1;
  @State keywordInput: string = '';
  @State coursesLoading: boolean = false;
  @State moreLoading: boolean = false;
  /** 正在提交选课的教学班 ID（同时只允许一个提交，防重复提交） */
  @State submittingId: string = '';
  @State tipText: string = '';
  @State isRefreshing: boolean = false;
  /** 状态栏避让区高度（px）：沉浸式全屏下内容顶部让位计算用 */
  @StorageProp('jwSafeTopPx') safeTopPx: number = 0;
  /** Refresh 布局高度：初始取屏幕高度，旋转后由窗口尺寸事件刷新（display 快照在旋转瞬间滞后） */
  @State refreshHeight: Length = '100%';
  /** 窗口尺寸变化回调：持有引用便于精准解绑，避免 off 误伤其他视图的监听 */
  private readonly onWinSizeChanged = (size: window.Size): void => {
    // 旋转：高度更新包进 animateTo，随其余页面的旋转动画一起平滑过渡
    this.getUIContext().animateTo({ duration: 420, curve: Curve.Friction }, () => {
      this.applyWindowHeightPx(size.height);
    });
  };

  aboutToAppear(): void {
    this.refreshHeight = this.refreshHeightVp();
    this.bindWindowHeight();
    this.loggedIn = SelectionRepository.isLoggedIn();
    if (this.loggedIn) {
      this.enterMain();
    }
  }

  aboutToDisappear(): void {
    this.unbindWindowHeight();
  }

  /** 应用回前台：重排轮次数组触发选课时间窗状态重算（进行中/已结束跨点切换） */
  onForegroundTick(): void {
    if (this.batches.length === 0) {
      return;
    }
    this.batches = this.batches.slice();
  }

  private contentMaxWidth(): number {
    return this.currentBreakpoint === 'sm' ? 600 : 1000;
  }

  private bottomInset(): number { return 88; }

  /**
   * Refresh 组件会接管子组件几何并吞掉其 expandSafeArea，导致内部 Scroll 的
   * 滚动视口无法扩展进安全避让区（内容永远裁剪在避让区上方）。
   * 因此不给 Refresh 走 expandSafeArea，而是显式把它的布局高度设为整屏高度
   * （窗口沉浸式全屏，布局从屏幕顶部开始），使 Refresh 与内部 Scroll
   * 的布局本身覆盖状态栏与底部手势区，滚动视口随布局自然延伸。
   */
  private refreshHeightVp(): Length {
    let screenHeightPx: number = 0;
    try {
      screenHeightPx = display.getDefaultDisplaySync().height;
    } catch (err) {
      screenHeightPx = 0;
    }
    if (screenHeightPx <= 0) {
      return '100%';
    }
    return this.getUIContext().px2vp(screenHeightPx);
  }

  /** 按窗口高度（px）刷新 Refresh 布局高度 */
  private applyWindowHeightPx(heightPx: number): void {
    if (heightPx > 0) {
      this.refreshHeight = this.getUIContext().px2vp(heightPx);
    }
  }

  /** 绑定主窗口尺寸变化：旋转后以窗口事件数据刷新 Refresh 高度（display 快照可能滞后） */
  private bindWindowHeight(): void {
    window.getLastWindow(getContext(this)).then((win: window.Window) => {
      this.applyWindowHeightPx(win.getWindowProperties().windowRect.height);
      win.on('windowSizeChange', this.onWinSizeChanged);
    }).catch(() => {
    });
  }

  /** 解绑窗口尺寸变化监听 */
  private unbindWindowHeight(): void {
    window.getLastWindow(getContext(this)).then((win: window.Window) => {
      win.off('windowSizeChange', this.onWinSizeChanged);
    }).catch(() => {
    });
  }

  private isSessionError(text: string): boolean { return plainError(text).indexOf(SESSION_INVALID_ERROR) >= 0; }

  /** 课程操作按钮文案：提交中/已选/已满/选课 */
  private courseActionLabel(course: SelectionCourse): string {
    if (this.submittingId === course.jxbId) {
      return '提交中';
    }
    if (this.isSelected(course.jxbId)) {
      return '已选';
    }
    if (course.capacity > 0 && course.selectedCount >= course.capacity) {
      return '已满';
    }
    return '选课';
  }

  private courseActionEnabled(course: SelectionCourse): boolean {
    return this.courseActionLabel(course) === '选课';
  }

  private isSelected(jxbId: string): boolean {
    for (const item of this.selectedCourses) {
      if (item.jxbId === jxbId) {
        return true;
      }
    }
    return false;
  }

  private hasMoreCourses(): boolean { return this.courses.length < this.totalCourses; }

  /** 主界面统一错误处理：会话失效回登录页，其余展示提示 */
  private handleMainError(errorText: string): void {
    if (this.isSessionError(errorText)) {
      this.backToLogin('选课会话已过期，请重新登录');
      return;
    }
    this.tipText = plainError(errorText);
  }

  private backToLogin(message: string): void {
    this.loggedIn = false;
    this.batches = [];
    this.courses = [];
    this.selectedCourses = [];
    this.totalCourses = 0;
    this.pageNumber = 1;
    this.currentBatchIndex = 0;
    this.tipText = '';
    this.studentNameText = '';
    this.loginResetMessage = message;
    // 递增重置信号：SelectionLoginPanel 回填提示并自动加载新验证码（uuid 与验证码成对，须整体换新）
    this.loginResetTick = this.loginResetTick + 1;
  }

  /** 登录成功进入主界面：拉取轮次、已选课程与课程列表 */
  private async enterMain(): Promise<void> {
    this.loggedIn = true;
    this.studentNameText = SelectionRepository.currentStudentName();
    this.tipText = '';
    await this.refreshBatches();
    await this.refreshSelected();
    await this.searchCourses(true);
  }

  private async refreshAll(): Promise<void> {
    this.tipText = '';
    await this.refreshBatches();
    await this.refreshSelected();
    await this.searchCourses(true);
  }

  /** 下拉刷新：已登录选课系统时刷新轮次、已选与课程列表；未登录时提示先登录 */
  private doRefresh(): void {
    if (!this.loggedIn) {
      this.isRefreshing = false;
      try {
        this.getUIContext().getPromptAction()
          .showToast({ message: '请先登录选课系统后再刷新', duration: 1500 });
      } catch (error) {
      }
      return;
    }
    this.refreshAll().then(() => {
      this.isRefreshing = false;
    });
  }

  private async refreshBatches(): Promise<void> {
    try {
      this.batches = await SelectionRepository.loadBatches();
      this.studentNameText = SelectionRepository.currentStudentName();
      if (this.currentBatchIndex >= this.batches.length) {
        this.currentBatchIndex = 0;
      }
    } catch (error) {
      this.handleMainError(`${error}`);
    }
  }

  private async refreshSelected(): Promise<void> {
    try {
      this.selectedCourses = await SelectionRepository.loadSelected();
    } catch (error) {
      this.handleMainError(`${error}`);
    }
  }

  /** 搜索/重置课程列表：reset 时回到第 1 页 */
  private async searchCourses(reset: boolean): Promise<void> {
    if (this.coursesLoading) {
      return;
    }
    if (reset) {
      this.pageNumber = 1;
    }
    this.coursesLoading = true;
    try {
      const result: CourseListResult =
        await SelectionRepository.loadCourses(this.keywordInput.trim(), this.pageNumber, PAGE_SIZE);
      if (this.pageNumber <= 1) {
        this.courses = result.courses;
      } else {
        this.courses = this.courses.concat(result.courses);
      }
      this.totalCourses = result.total;
    } catch (error) {
      this.handleMainError(`${error}`);
    } finally {
      this.coursesLoading = false;
    }
  }

  /** 加载下一页（查询可重试，仅提交选课不可重试） */
  private async loadMoreCourses(): Promise<void> {
    if (this.moreLoading || this.coursesLoading) {
      return;
    }
    if (!this.hasMoreCourses()) {
      return;
    }
    this.moreLoading = true;
    this.pageNumber = this.pageNumber + 1;
    try {
      const result: CourseListResult =
        await SelectionRepository.loadCourses(this.keywordInput.trim(), this.pageNumber, PAGE_SIZE);
      this.courses = this.courses.concat(result.courses);
      this.totalCourses = result.total;
    } catch (error) {
      this.pageNumber = this.pageNumber - 1;
      this.handleMainError(`${error}`);
    } finally {
      this.moreLoading = false;
    }
  }

  /** 提交前确认：校验轮次、重复选课与时间窗，弹确认框防误触（提交不可撤销） */
  private confirmSubmit(course: SelectionCourse): void {
    if (this.submittingId.length > 0) {
      return;
    }
    const batch: SelectionBatch | undefined = this.batches[this.currentBatchIndex];
    if (batch === undefined) {
      this.tipText = '未获取到选课轮次，请点击刷新后重试';
      return;
    }
    if (this.isSelected(course.jxbId)) {
      this.tipText = '该课程已在已选列表中';
      return;
    }
    const status: string = batchStatus(batch);
    if (status === '已结束' || status === '未开放') {
      this.tipText = '当前轮次不在选课时间内：' + status;
      return;
    }
    const params: AlertDialogParamWithButtons = {
      title: '确认选课',
      message: '将提交「' + course.courseName + '」（' + course.teacher + '）。提交仅执行一次且不可撤销，确认继续吗？',
      primaryButton: {
        value: '取消',
        action: (): void => {
        }
      },
      secondaryButton: {
        value: '确认选课',
        action: (): void => {
          this.doSubmit(course);
        }
      }
    };
    this.getUIContext().showAlertDialog(params);
  }

  /**
   * 提交选课：只提交一次、绝不重试；
   * 网络异常时结果未知，提示用户回查已选列表确认，切勿盲目重复提交。
   */
  private async doSubmit(course: SelectionCourse): Promise<void> {
    const batch: SelectionBatch | undefined = this.batches[this.currentBatchIndex];
    if (batch === undefined) {
      return;
    }
    this.submittingId = course.jxbId;
    this.tipText = '';
    let sessionLost: boolean = false;
    try {
      const outcome: SelectionOutcome = await SelectionRepository.submitCourse(course, batch.code);
      if (outcome.success) {
        this.tipText = outcome.message;
      } else {
        this.tipText = '选课失败：' + outcome.message;
      }
    } catch (error) {
      if (this.isSessionError(`${error}`)) {
        sessionLost = true;
      } else {
        this.tipText = '提交请求异常（已按规则不再重试）：' + plainError(`${error}`)
          + '。请刷新已选列表确认结果，切勿盲目重复提交。';
      }
    } finally {
      this.submittingId = '';
    }
    if (sessionLost) {
      this.backToLogin('选课会话已过期，请重新登录');
      return;
    }
    await this.refreshSelected();
    await this.searchCourses(true);
  }

  private async doLogout(): Promise<void> {
    await SelectionRepository.logout();
    this.backToLogin('');
  }

  @Builder
  mainContent() {
    Column({ space: 12 }) {
      SelectionHeaderCard(loginSummaryText(this.studentNameText, this.selectedCourses.length),
        (): void => {
          this.refreshAll();
        }, (): void => {
          this.doLogout();
        })
      if (this.tipText.length > 0) {
        SelectionTipCard(this.tipText)
      }
      if (this.batches.length === 0) {
        SelectionCoursesEmptyCard(this.keywordInput.length > 0)
      } else {
        SelectionBatchSection(this.batches, this.currentBatchIndex, (index: number): void => {
          this.currentBatchIndex = index;
        })
      }
      SelectionSelectedCard(this.selectedCourses)
      SelectionSearchRow(this.keywordInput, !this.coursesLoading, (value: string): void => {
        this.keywordInput = value;
      }, (): void => {
        this.searchCourses(true);
      })
      if (this.coursesLoading && this.courses.length === 0) {
        SelectionCoursesLoadingCard()
      } else if (this.courses.length === 0) {
        SelectionCoursesEmptyCard(this.keywordInput.length > 0)
      } else {
        Text(totalCourseText(this.totalCourses))
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        ForEach(this.courses, (course: SelectionCourse) => {
          SelectionCourseCard(course, this.courseActionLabel(course), this.courseActionEnabled(course),
            (): void => {
              this.confirmSubmit(course);
            })
        }, (course: SelectionCourse) => course.jxbId)
        SelectionLoadMoreRow(this.moreLoading, this.hasMoreCourses(), (): void => {
          this.loadMoreCourses();
        })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Refresh({ refreshing: $$this.isRefreshing }) {
      Scroll() {
        Column() {
          if (this.loggedIn) {
            this.mainContent()
          } else {
            SelectionLoginPanel({
              loggedIn: this.loggedIn,
              resetTick: this.loginResetTick,
              resetMessage: this.loginResetMessage,
              onLoginSuccess: (): Promise<void> => this.enterMain()
            })
          }
        }
        .padding({ left: 16, right: 16, top: frostTopInsetVp(this.safeTopPx, this.getUIContext()), bottom: this.bottomInset() })
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ minWidth: '100%', maxWidth: this.contentMaxWidth() })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      }
      .onRefreshing(() => {
        this.doRefresh();
      })
      .width('100%')
      .height(this.refreshHeight)

      FrostBand()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
