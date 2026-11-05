import {
  CaptchaData,
  CourseListResult,
  SelectionBatch,
  SelectionCredentials,
  SelectionCourse,
  SelectionOutcome,
  SelectedCourse
} from '../model/SelectionModels';
import { SelectionRepository, SESSION_INVALID_ERROR } from '../data/SelectionRepository';
import { FrostBand, FROST_BAND_HEIGHT } from './FrostBand';

/** 课程列表每页条数（接口 pageSize） */
const PAGE_SIZE: number = 10;
/** 提示语颜色（警示） */
const WARN_COLOR: string = '#E84026';
/** 轮次未开始状态色 */
const PENDING_COLOR: string = '#E88A00';

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
  /** 选课页签是否处于激活（可见）状态：首次激活且未登录时自动加载验证码 */
  @StorageProp('jwSelectionTabActive') @Watch('onSelectionTabActive') selectionTabActive: boolean = false;
  /** 是否已登录选课系统（凭证仅内存态，冷启动后为 false） */
  @State loggedIn: boolean = false;
  @State loginBusy: boolean = false;
  @State loginError: string = '';
  @State studentIdInput: string = '';
  @State passwordInput: string = '';
  @State captchaInput: string = '';
  /** 登录成功后是否记住学号和密码（存于系统关键资产存储，仅本机） */
  @State rememberCredentials: boolean = true;
  @State captchaData: CaptchaData | null = null;
  @State captchaBusy: boolean = false;
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

  aboutToAppear(): void {
    this.loggedIn = SelectionRepository.isLoggedIn();
    if (this.loggedIn) {
      this.enterMain();
      return;
    }
    this.loadSavedCredentials();
    this.fetchCaptchaIfNeeded();
  }

  /** 应用回前台：重排轮次数组触发选课时间窗状态重算（进行中/已结束跨点切换） */
  onForegroundTick(): void {
    if (this.batches.length === 0) {
      return;
    }
    this.batches = this.batches.slice();
  }

  /** 选课页签激活：登录页可见时自动加载图形验证码，无需手动点击 */
  onSelectionTabActive(): void {
    this.fetchCaptchaIfNeeded();
  }

  /** 回填已保存的登录凭据（密码可能为空：登录尝试时仅保存学号）；读取失败静默降级为不回填 */
  private async loadSavedCredentials(): Promise<void> {
    try {
      const saved: SelectionCredentials | null = await SelectionRepository.loadCredentials();
      if (saved === null) {
        return;
      }
      this.studentIdInput = saved.loginName;
      this.passwordInput = saved.password;
      this.rememberCredentials = true;
    } catch (error) {
      // 已保存凭据不可用时不阻塞登录流程
    }
  }

  /** 切换「记住学号和密码」：取消勾选立即清除已保存的凭据 */
  private onRememberToggle(value: boolean): void {
    this.rememberCredentials = value;
    if (!value) {
      SelectionRepository.clearSavedCredentials();
    }
  }

  /** 登录页可见且尚无验证码时自动获取（页签未激活、已登录或加载中不重复请求） */
  private fetchCaptchaIfNeeded(): void {
    if (!this.selectionTabActive || this.loggedIn) {
      return;
    }
    if (this.captchaData !== null || this.captchaBusy) {
      return;
    }
    this.refreshCaptcha();
  }

  private contentMaxWidth(): number {
    if (this.currentBreakpoint === 'sm') {
      return 600;
    }
    return 1000;
  }

  private bottomInset(): number {
    return 88;
  }

  /** 去掉 Error 字符串的 'Error: ' 前缀，便于直接展示 */
  private plainError(text: string): string {
    return text.startsWith('Error: ') ? text.substring(7) : text;
  }

  private isSessionError(text: string): boolean {
    return this.plainError(text).indexOf(SESSION_INVALID_ERROR) >= 0;
  }

  /** 验证码图片（type=1 图形验证码时返回 Data URI，其余返回空串） */
  private captchaImage(): string {
    if (this.captchaData === null || this.captchaData.type !== 1) {
      return '';
    }
    return this.captchaData.captcha;
  }

  /** 是否为交互式验证码（type=2，App 暂不支持，需引导刷新换图形验证码） */
  private captchaIsInteractive(): boolean {
    return this.captchaData !== null && this.captchaData.type === 2;
  }

  private captchaButtonText(): string {
    if (this.captchaBusy) {
      return '获取中…';
    }
    if (this.captchaData === null) {
      return '获取验证码';
    }
    return '换一张';
  }

  private loginButtonLabel(): string {
    return this.loginBusy ? '登录中…' : '登录';
  }

  private loginSummaryText(): string {
    return this.studentNameText + ' · 已选 ' + `${this.selectedCourses.length}` + ' 门';
  }

  private totalCourseText(): string {
    return '共 ' + `${this.totalCourses}` + ' 门课程';
  }

  /** 当前选中轮次的时间窗文本 */
  private batchTimeText(): string {
    const batch: SelectionBatch | undefined = this.batches[this.currentBatchIndex];
    if (batch === undefined) {
      return '';
    }
    return batch.beginTime + ' ~ ' + batch.endTime;
  }

  /** 轮次选课时间状态：未开放/未开始/进行中/已结束/可选 */
  private batchStatus(batch: SelectionBatch): string {
    if (batch.canSelect !== '1') {
      return '未开放';
    }
    const begin: number = this.parseTime(batch.beginTime);
    const end: number = this.parseTime(batch.endTime);
    const now: number = Date.now();
    if (begin > 0 && now < begin) {
      return '未开始';
    }
    if (end > 0 && now > end) {
      return '已结束';
    }
    if (begin > 0 && end > 0) {
      return '进行中';
    }
    return '可选';
  }

  /** 宽容解析 'YYYY-MM-DD HH:mm:ss' 等数字时间文本，失败返回 0 */
  private parseTime(text: string): number {
    if (text.length < 8) {
      return 0;
    }
    const parts: string[] = text.split(/[^0-9]+/);
    const nums: number[] = [];
    for (const part of parts) {
      if (part.length > 0) {
        nums.push(Number.parseInt(part));
      }
    }
    if (nums.length < 3) {
      return 0;
    }
    const hour: number = nums.length > 3 ? nums[3] : 0;
    const minute: number = nums.length > 4 ? nums[4] : 0;
    const date: Date = new Date(nums[0], nums[1] - 1, nums[2], hour, minute);
    const time: number = date.getTime();
    return Number.isNaN(time) ? 0 : time;
  }

  private statusColor(status: string): ResourceColor {
    if (status === '进行中' || status === '可选') {
      return $r('sys.color.ohos_id_color_text_primary_activated');
    }
    if (status === '未开始') {
      return PENDING_COLOR;
    }
    return $r('sys.color.ohos_id_color_text_secondary');
  }

  private courseSubText(course: SelectionCourse): string {
    const teacher: string = course.teacher.length > 0 ? course.teacher : '教师待定';
    if (course.timeText.length > 0) {
      return teacher + ' · ' + course.timeText;
    }
    return teacher;
  }

  private courseCountText(course: SelectionCourse): string {
    return '已选 ' + `${course.selectedCount}` + '/' + `${course.capacity}`;
  }

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

  private selectedStatusText(item: SelectedCourse): string {
    return item.selectStatus === 99 ? '正常' : '状态 ' + `${item.selectStatus}`;
  }

  private selectedSubText(item: SelectedCourse): string {
    const credit: string = item.credit.length > 0 ? ' · ' + item.credit + '学分' : '';
    return item.teacher + credit;
  }

  private hasMoreCourses(): boolean {
    return this.courses.length < this.totalCourses;
  }

  /** 主界面统一错误处理：会话失效回登录页，其余展示提示 */
  private handleMainError(errorText: string): void {
    if (this.isSessionError(errorText)) {
      this.backToLogin('选课会话已过期，请重新登录');
      return;
    }
    this.tipText = this.plainError(errorText);
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
    this.captchaData = null;
    if (message.length > 0) {
      this.loginError = message;
    }
    // 回到登录页即自动加载新验证码（uuid 与验证码成对，须整体换新）
    this.refreshCaptcha();
  }

  /** 获取/刷新图形验证码（每次刷新换新 uuid，与验证码成对使用） */
  private async refreshCaptcha(): Promise<void> {
    if (this.captchaBusy) {
      return;
    }
    this.captchaBusy = true;
    try {
      this.captchaData = await SelectionRepository.fetchCaptcha();
      this.captchaInput = '';
    } catch (error) {
      this.loginError = '获取验证码失败：' + this.plainError(`${error}`);
    } finally {
      this.captchaBusy = false;
    }
  }

  private async doLogin(): Promise<void> {
    if (this.loginBusy) {
      return;
    }
    // 勾选「记住」时，登录尝试即先记住学号（密码待登录成功后才保存，避免记住输错的密码）
    if (this.rememberCredentials && this.studentIdInput.length > 0) {
      await SelectionRepository.saveLoginNameDraft(this.studentIdInput);
    }
    if (this.studentIdInput.length === 0 || this.passwordInput.length === 0) {
      this.loginError = '请填写学号和密码';
      return;
    }
    if (this.captchaData === null) {
      this.loginError = '请先获取验证码';
      return;
    }
    if (this.captchaInput.length === 0) {
      this.loginError = '请填写验证码';
      return;
    }
    this.loginBusy = true;
    this.loginError = '';
    try {
      const uuid: string = this.captchaData.uuid;
      await SelectionRepository.login(this.studentIdInput, this.passwordInput, this.captchaInput, uuid);
      // 登录成功后按勾选状态保存/清除凭据（存于系统关键资产存储，仅本机）
      if (this.rememberCredentials) {
        await SelectionRepository.saveCredentials(this.studentIdInput, this.passwordInput);
      } else {
        await SelectionRepository.clearSavedCredentials();
      }
      await this.enterMain();
    } catch (error) {
      this.loginError = this.plainError(`${error}`);
      this.refreshCaptcha();
    } finally {
      this.loginBusy = false;
    }
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
    const status: string = this.batchStatus(batch);
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
        this.tipText = '提交请求异常（已按规则不再重试）：' + this.plainError(`${error}`)
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
  loginCard() {
    Column({ space: 6 }) {
      SymbolGlyph($r('sys.symbol.list_bullet'))
        .fontSize(36)
        .fontColor([$r('sys.color.ohos_id_color_text_primary_activated')])
      Text('选课系统')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
      Text('使用选课系统账号登录（可能与教务账号不同），数据实时获取、不缓存。')
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 24, bottom: 24, left: 20, right: 20 })
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  loginForm() {
    Column({ space: 10 }) {
      TextInput({ placeholder: '学号', text: this.studentIdInput })
        .fontSize(14)
        .height(44)
        .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
        .borderRadius(12)
        .onChange((value: string) => {
          this.studentIdInput = value;
        })
      TextInput({ placeholder: '密码', text: this.passwordInput })
        .fontSize(14)
        .height(44)
        .type(InputType.Password)
        .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
        .borderRadius(12)
        .onChange((value: string) => {
          this.passwordInput = value;
        })
      Row({ space: 10 }) {
        TextInput({ placeholder: '验证码', text: this.captchaInput })
          .fontSize(14)
          .height(44)
          .layoutWeight(1)
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .borderRadius(12)
          .onChange((value: string) => {
            this.captchaInput = value;
          })
        if (this.captchaImage().length > 0) {
          Image(this.captchaImage())
            .height(44)
            .objectFit(ImageFit.Contain)
            .borderRadius(8)
            .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
            .onClick(() => {
              this.refreshCaptcha();
            })
        }
        Button(this.captchaButtonText())
          .fontSize(13)
          .height(44)
          .enabled(!this.captchaBusy)
          .onClick(() => {
            this.refreshCaptcha();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      if (this.captchaIsInteractive()) {
        Text('当前为交互式验证码，App 暂不支持，请点击「换一张」直至出现图形验证码。')
          .fontSize(11)
          .fontColor(WARN_COLOR)
      }
      Row({ space: 8 }) {
        Checkbox()
          .select(this.rememberCredentials)
          .selectedColor($r('sys.color.ohos_id_color_text_primary_activated'))
          .width(18)
          .height(18)
          .onChange((value: boolean) => {
            this.onRememberToggle(value);
          })
        Text('记住学号和密码（仅保存在本机系统安全存储）')
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .layoutWeight(1)
          .maxLines(2)
          .onClick(() => {
            this.onRememberToggle(!this.rememberCredentials);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      if (this.loginError.length > 0) {
        Text(this.loginError)
          .fontSize(12)
          .fontColor(WARN_COLOR)
      }
      Button(this.loginButtonLabel())
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .height(44)
        .enabled(!this.loginBusy)
        .onClick(() => {
          this.doLogin();
        })
      Text('密码经 HTTPS 直接发送至选课系统（服务端要求 AES 加密后提交），登录凭证仅保留在内存。勾选「记住学号和密码」后，学号在登录时即保存、密码于登录成功后保存，均仅存于本机系统安全存储（关键资产）；取消勾选或切换到受限/严格隐私模式时立即清除。')
        .fontSize(11)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .margin({ top: 12 })
  }

  @Builder
  loginContent() {
    Column() {
      this.loginCard()
      this.loginForm()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  tipCard() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(18)
        .fontColor([$r('sys.color.ohos_id_color_text_primary_activated')])
      Text(this.tipText)
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  headerCard() {
    Row({ space: 8 }) {
      Column({ space: 2 }) {
        Text('选课系统')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
        Text(this.loginSummaryText())
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Button('刷新')
        .fontSize(13)
        .height(34)
        .onClick(() => {
          this.refreshAll();
        })
      Button('退出')
        .fontSize(13)
        .height(34)
        .onClick(() => {
          this.doLogout();
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding(12)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  batchChip(batch: SelectionBatch, index: number) {
    Text(batch.name.length > 0 ? batch.name : '轮次')
      .fontSize(13)
      .fontColor(index === this.currentBatchIndex ? Color.White : $r('sys.color.ohos_id_color_text_primary'))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .constraintSize({ maxWidth: 220 })
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .borderRadius(16)
      .backgroundColor(index === this.currentBatchIndex
        ? $r('sys.color.ohos_id_color_text_primary_activated')
        : $r('app.color.card_background'))
      .onClick(() => {
        this.currentBatchIndex = index;
      })
  }

  @Builder
  batchSection() {
    Column({ space: 10 }) {
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.batches, (batch: SelectionBatch, index: number) => {
            this.batchChip(batch, index)
          }, (batch: SelectionBatch) => batch.code)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      if (this.batches.length > 0) {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Text(this.batches[this.currentBatchIndex].name)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('sys.color.ohos_id_color_text_primary'))
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.batchStatus(this.batches[this.currentBatchIndex]))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.statusColor(this.batchStatus(this.batches[this.currentBatchIndex])))
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          Text('选课时间：' + this.batchTimeText())
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          if (this.batches[this.currentBatchIndex].typeName.length > 0
            || this.batches[this.currentBatchIndex].tacticName.length > 0) {
            Text(this.batches[this.currentBatchIndex].typeName
              + (this.batches[this.currentBatchIndex].tacticName.length > 0
                ? ' · ' + this.batches[this.currentBatchIndex].tacticName
                : ''))
              .fontSize(12)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          if (this.batches[this.currentBatchIndex].weekRange.length > 0) {
            Text('上课周次：' + this.batches[this.currentBatchIndex].weekRange)
              .fontSize(12)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(12)
        .borderRadius(16)
        .backgroundColor($r('app.color.card_background'))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  selectedCard() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text('已选课程')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .layoutWeight(1)
        Text(`${this.selectedCourses.length}` + ' 门')
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      if (this.selectedCourses.length === 0) {
        Text('暂无已选课程，选课提交后在此显示，可下拉刷新查看最新结果。')
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      } else {
        ForEach(this.selectedCourses, (item: SelectedCourse) => {
          Row({ space: 8 }) {
            Column({ space: 2 }) {
              Text(item.courseName)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.ohos_id_color_text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.selectedSubText(item))
                .fontSize(11)
                .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Text(this.selectedStatusText(item))
              .fontSize(11)
              .fontColor(item.selectStatus === 99
                ? $r('sys.color.ohos_id_color_text_primary_activated')
                : $r('sys.color.ohos_id_color_text_secondary'))
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }, (item: SelectedCourse) => item.jxbId)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  searchRow() {
    Row({ space: 8 }) {
      TextInput({ placeholder: '搜索课程名或教师', text: this.keywordInput })
        .fontSize(13)
        .height(40)
        .layoutWeight(1)
        .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
        .borderRadius(20)
        .onChange((value: string) => {
          this.keywordInput = value;
        })
      Button('搜索')
        .fontSize(13)
        .height(40)
        .enabled(!this.coursesLoading)
        .onClick(() => {
          this.searchCourses(true);
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  courseCard(course: SelectionCourse) {
    Column({ space: 8 }) {
      Row() {
        Text(course.courseName)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(course.credit + '学分')
          .fontSize(11)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .margin({ left: 8 })
      }
      .width('100%')
      Text(this.courseSubText(course))
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Row() {
        Text(this.courseCountText(course))
          .fontSize(11)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .layoutWeight(1)
        Button(this.courseActionLabel(course))
          .fontSize(13)
          .height(32)
          .padding({ left: 16, right: 16 })
          .enabled(this.courseActionEnabled(course))
          .onClick(() => {
            this.confirmSubmit(course);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  coursesLoadingCard() {
    Column({ space: 10 }) {
      LoadingProgress()
        .width(28)
        .height(28)
      Text('正在加载课程…')
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 28, bottom: 28 })
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  coursesEmptyCard() {
    Column({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.list_bullet'))
        .fontSize(36)
        .fontColor([$r('sys.color.ohos_id_color_text_secondary')])
      Text(this.keywordInput.length > 0 ? '未找到相关课程' : '暂无可选课程')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
      Text('换个关键词试试，或点击右上角刷新。')
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 28, bottom: 28, left: 24, right: 24 })
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  loadMoreRow() {
    Column() {
      if (this.moreLoading) {
        Row({ space: 8 }) {
          LoadingProgress()
            .width(20)
            .height(20)
          Text('正在加载…')
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        }
        .alignItems(VerticalAlign.Center)
      } else if (this.hasMoreCourses()) {
        Button('加载更多')
          .fontSize(13)
          .height(36)
          .onClick(() => {
            this.loadMoreCourses();
          })
      } else {
        Text('没有更多了')
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .margin({ top: 4 })
  }

  @Builder
  mainContent() {
    Column({ space: 12 }) {
      this.headerCard()
      if (this.tipText.length > 0) {
        this.tipCard()
      }
      if (this.batches.length === 0) {
        this.coursesEmptyCard()
      } else {
        this.batchSection()
      }
      this.selectedCard()
      this.searchRow()
      if (this.coursesLoading && this.courses.length === 0) {
        this.coursesLoadingCard()
      } else if (this.courses.length === 0) {
        this.coursesEmptyCard()
      } else {
        Text(this.totalCourseText())
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        ForEach(this.courses, (course: SelectionCourse) => {
          this.courseCard(course)
        }, (course: SelectionCourse) => course.jxbId)
        this.loadMoreRow()
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
            this.loginContent()
          }
        }
        .padding({ left: 16, right: 16, top: FROST_BAND_HEIGHT, bottom: this.bottomInset() })
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ minWidth: '100%', maxWidth: this.contentMaxWidth() })
      }
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .scrollBar(BarState.Off)
      }
      .onRefreshing(() => {
        this.doRefresh();
      })

      FrostBand()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
