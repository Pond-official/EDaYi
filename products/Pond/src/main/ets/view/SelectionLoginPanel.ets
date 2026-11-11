import { CaptchaData, SelectionCredentials } from '../model/SelectionModels';
import { SelectionRepository } from '../data/SelectionRepository';
import { plainError } from './SelectionCards';
import { REJECT_TEXT } from '../theme/AppColors';

/** 提示语颜色（警示） */
const WARN_COLOR: string = REJECT_TEXT;

/**
 * 选课登录面板（自 SelectionView 整体拆出）：
 * 学号 + 密码 + 图形验证码原生登录（密码按服务端要求 AES-128-ECB 加密提交），
 * 登录凭证仅保留在内存，不缓存任何选课数据；
 * 勾选「记住学号和密码」后凭据仅存于本机系统关键资产存储。
 */
@Component
export struct SelectionLoginPanel {
  /** 选课页签是否处于激活（可见）状态：首次激活且未登录时自动加载验证码 */
  @StorageProp('jwSelectionTabActive') @Watch('onSelectionTabActive') selectionTabActive: boolean = false;
  /** 父组件当前登录态（面板仅未登录时挂载，挂载期恒为 false，保留原判断） */
  @Prop loggedIn: boolean = false;
  /** 父组件触发的重置信号：会话失效/退出登录回到登录页时递增，面板换新验证码 */
  @Prop @Watch('onResetTick') resetTick: number = 0;
  /** 回到登录页时要展示的提示（会话过期原因等，空串不覆盖） */
  @Prop resetMessage: string = '';
  /** 登录成功回调：由父组件接管进入主界面（拉取轮次、已选课程与课程列表） */
  onLoginSuccess: () => Promise<void> = (): Promise<void> => Promise.resolve();
  @State studentIdInput: string = '';
  @State passwordInput: string = '';
  @State captchaInput: string = '';
  /** 登录成功后是否记住学号和密码（存于系统关键资产存储，仅本机） */
  @State rememberCredentials: boolean = true;
  @State captchaData: CaptchaData | null = null;
  @State captchaBusy: boolean = false;
  @State loginBusy: boolean = false;
  @State loginError: string = '';

  aboutToAppear(): void {
    // 会话失效/退出登录后重新挂载：回填父组件带回登录页时的提示
    if (this.resetMessage.length > 0) {
      this.loginError = this.resetMessage;
    }
    this.loadSavedCredentials();
    this.fetchCaptchaIfNeeded();
  }

  /** 选课页签激活：登录页可见时自动加载图形验证码，无需手动点击 */
  onSelectionTabActive(): void {
    this.fetchCaptchaIfNeeded();
  }

  /** 父组件触发重置（会话失效/退出登录）：展示带回登录页的原因并换新验证码 */
  onResetTick(): void {
    if (this.resetMessage.length > 0) {
      this.loginError = this.resetMessage;
    }
    this.captchaData = null;
    // 回到登录页即自动加载新验证码（uuid 与验证码成对，须整体换新）
    this.refreshCaptcha();
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
      this.loginError = '获取验证码失败：' + plainError(`${error}`);
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
      await this.onLoginSuccess();
    } catch (error) {
      this.loginError = plainError(`${error}`);
      this.refreshCaptcha();
    } finally {
      this.loginBusy = false;
    }
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

  build() {
    Column() {
      this.loginContent()
    }
    .width('100%')
  }
}
