import { webview } from '@kit.ArkWeb';
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { JwxtRepository } from '../data/JwxtRepository';

const TAG: string = 'LoginIndex';
const DOMAIN: number = 0x0000;

/**
 * 教务系统登录页：内嵌 WebView 走学校统一身份认证（CAS），
 * 登录成功后会话 Cookie 落入 WebCookieManager，供 HTTP 数据层共享。
 * 注意：CAS 页面脚本依赖 DOM Storage，必须开启 domStorageAccess，
 * 否则登录按钮的点击事件脚本异常，表现为按钮无法点击。
 *
 * 交互约定：
 * - 2 秒轮询 + onPageEnd 自动探测会话；
 * - 探测通过后先同步教务数据，同步成功才自动返回主界面；
 * - 同步失败时解除锁定，按钮恢复可用，可点击"完成"重试；
 * - 返回键仅依据页面栈 index 判断，避免字符串比对卡死。
 */
@Entry
@Component
struct LoginIndex {
  private webController: webview.WebviewController = new webview.WebviewController();
  @State pageTitle: string = '教务系统登录';
  private checking: boolean = false;
  private syncing: boolean = false;
  private leaving: boolean = false;
  private detectTimer: number = -1;

  aboutToAppear(): void {
    this.detectTimer = setInterval(() => {
      this.detectSession();
    }, 2000);
  }

  aboutToDisappear(): void {
    this.leaving = true;
    if (this.detectTimer >= 0) {
      clearInterval(this.detectTimer);
      this.detectTimer = -1;
    }
  }

  private handlePageEnd(): void {
    let endedUrl: string = '';
    try {
      endedUrl = this.webController.getUrl();
    } catch (error) {
      endedUrl = '';
    }
    hilog.info(DOMAIN, TAG, 'page end: %{public}s', endedUrl);
    this.detectSession();
  }

  /**
   * 登录态检测：页面落在教务系统域名时探测会话，成功则进入同步并自动返回流程。
   */
  private detectSession(): void {
    if (this.checking || this.syncing || this.leaving) {
      return;
    }
    let currentUrl: string = '';
    try {
      currentUrl = this.webController.getUrl();
    } catch (error) {
      return;
    }
    if (currentUrl.indexOf('jwxt.dmu.edu.cn') < 0 || currentUrl.indexOf('authserver') >= 0) {
      return;
    }
    this.checking = true;
    hilog.info(DOMAIN, TAG, 'detect probe start, url=%{public}s', currentUrl);
    JwxtRepository.probeSession().then((ok: boolean) => {
      this.checking = false;
      hilog.info(DOMAIN, TAG, 'detect probe result: %{public}s', `${ok}`);
      if (ok && !this.leaving && !this.syncing) {
        this.syncAndReturn();
      }
    }).catch((error: BusinessError) => {
      this.checking = false;
      hilog.error(DOMAIN, TAG, 'detect probe error: %{public}s %{public}s',
        `${error.code}`, `${error.message}`);
    });
  }

  /**
   * 登录已确认：同步教务数据，成功后自动返回主界面；
   * 失败则解除 syncing 锁定，"完成"按钮恢复可用以便重试。
   */
  private syncAndReturn(): void {
    if (this.syncing || this.leaving) {
      return;
    }
    this.syncing = true;
    this.showPrompt('登录成功，正在同步教务数据…', 1500);
    hilog.info(DOMAIN, TAG, 'sync and return: start');
    JwxtRepository.reload().then((ok: boolean) => {
      hilog.info(DOMAIN, TAG, 'sync and return: result %{public}s', `${ok}`);
      if (this.leaving) {
        return;
      }
      if (ok) {
        this.backToHome();
      } else {
        this.syncing = false;
        this.showPrompt('数据同步失败，请检查网络后点击完成重试', 2000);
      }
    }).catch((error: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'sync and return: error %{public}s %{public}s',
        `${error.code}`, `${error.message}`);
      if (this.leaving) {
        return;
      }
      this.syncing = false;
      this.showPrompt('数据同步失败，请检查网络后点击完成重试', 2000);
    });
  }

  /**
   * 手动完成：独立执行探测，不受轮询影响；探测通过走同一同步返回流程。
   */
  private manualSync(): void {
    if (this.leaving) {
      return;
    }
    if (this.syncing) {
      this.showPrompt('正在同步教务数据，请稍候…', 1500);
      return;
    }
    this.showPrompt('正在检测登录状态…', 1000);
    hilog.info(DOMAIN, TAG, 'manual: probe start');
    JwxtRepository.probeSession().then((ok: boolean) => {
      hilog.info(DOMAIN, TAG, 'manual: probe result %{public}s', `${ok}`);
      if (this.leaving) {
        return;
      }
      if (ok) {
        this.syncAndReturn();
      } else {
        this.showPrompt('尚未登录成功，请先在页面中完成登录', 1500);
      }
    }).catch((error: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'manual: probe error %{public}s %{public}s',
        `${error.code}`, `${error.message}`);
      if (this.leaving) {
        return;
      }
      this.showPrompt('网络异常，请稍后重试', 1500);
    });
  }

  private showPrompt(message: string, duration: number): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: duration });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'showToast failed: %{public}s', `${error}`);
    }
  }

  /**
   * 返回主页：依据页面栈位置判断（index>1 才 back），
   * 避免字符串比对失败导致返回键失效；同时记录栈状态便于诊断。
   */
  private backToHome(): void {
    this.leaving = true;
    try {
      const state: router.RouterState = router.getState();
      hilog.info(DOMAIN, TAG, 'back: index=%{public}d path=%{public}s',
        state.index, state.path);
      if (state.index > 1) {
        router.back();
      } else {
        hilog.error(DOMAIN, TAG, 'back aborted: login page is root');
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'router back failed: %{public}s', `${error}`);
    }
  }

  build() {
    Column() {
      Row() {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(24)
            .fontColor([$r('sys.color.titlebar_icon_color')])
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.backToHome();
        })
        Text(this.pageTitle)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .layoutWeight(1)
        Text(this.syncing ? '同步中…' : '完成')
          .fontSize(15)
          .fontColor($r('sys.color.ohos_id_color_text_primary_activated'))
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .borderRadius(16)
          .onClick(() => {
            this.manualSync();
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 8 })
      .alignItems(VerticalAlign.Center)
      Web({ src: JwxtRepository.loginUrl(), controller: this.webController })
        .layoutWeight(1)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .databaseAccess(true)
        .onPageEnd(() => {
          this.handlePageEnd();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
