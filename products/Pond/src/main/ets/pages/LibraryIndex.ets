import { LoanPage, LoanRecord, RenewResult } from '../model/LibraryModels';
import { LibraryRepository } from '../data/LibraryRepository';
import { EhallRepository } from '../data/EhallRepository';
import { CrossDomainSession } from '../net/CrossDomainSession';
import { DOMAIN_LIBSP } from '../net/DomainSpec';
import { LIBSP_SESSION_INVALID } from '../net/LibSpTransport';
import { FrostBand, FROST_BAND_HEIGHT, frostTopInsetVp } from '../view/FrostBand';
import { BackButton } from '../view/BackButton';
import { plainError } from '../view/ZcpCards';
import { LibraryErrorCard, LibraryHistoryCard, LibraryLoadingCard, LibraryLoansCard } from '../view/LibraryCards';

/** 令牌重读间隔（ms）：SSO 落地后前端写 cookie 略滞后于 onPageEnd，轮询重试 */
const TOKEN_RETRY_INTERVAL_MS: number = 500;
/** 令牌重读次数 */
const TOKEN_RETRY_COUNT: number = 6;

/**
 * 图书借阅详情页（独立路由页）：当前借阅（含续借）+ 借阅历史。
 * 会话建立：图书馆不在教务域而在 finddmu.libsp.cn（汇文 LibSP），
 * 经超星 CAS 中转的 SSO 链换取 JWT（cookie 键 jwt/jwtHeader），
 * 首次进入由全 App 唯一的跨域会话服务（net/CrossDomainSession，
 * 根页面常驻隐藏 Web 承载）加载超星入口完成整条重定向链；
 * JWT 有效期 24 小时无 refresh，过期自动重换票重试一次；
 * 数据仅内存态（借阅明细不做磁盘缓存），每次进入在线拉取。
 */
@Entry
@Component
struct LibraryIndex {
  /** 教务数据模式：未登录（preview/offlineCache）时提示先登录 */
  @StorageProp('jwDataMode') dataMode: string = 'preview';
  /** 状态栏避让区高度（px）：沉浸式全屏下内容顶部让位计算用 */
  @StorageProp('jwSafeTopPx') safeTopPx: number = 0;
  /** idle=未加载 bootstrap=跨域换票中 loading=业务拉取中 error=失败 */
  @State phase: string = 'idle';
  @State errorText: string = '';
  /** 当前借阅（含剩余可借数） */
  @State loans: LoanPage = new LoanPage();
  /** 借阅历史 */
  @State history: LoanPage = new LoanPage();
  /** 正在续借的 loanId（0 = 无在途续借） */
  @State renewingLoanId: number = 0;

  aboutToAppear(): void {
    this.start();
  }

  /** 启动加载：已有有效令牌直接拉数据，否则先走隐藏 Web 换票（SSO 链落 JWT cookie） */
  private async start(): Promise<void> {
    if (this.phase === 'bootstrap' || this.phase === 'loading') {
      return;
    }
    if (this.dataMode !== 'online') {
      this.phase = 'error';
      this.errorText = '请先在「首页」登录教务系统，再查看图书借阅';
      return;
    }
    this.errorText = '';
    if (!LibraryRepository.hasToken() && !LibraryRepository.bindTokenFromCookie()) {
      const bound: boolean = await this.rebindToken();
      if (!bound) {
        this.phase = 'error';
        this.errorText = '未能建立图书馆会话，请稍后重试';
        return;
      }
    }
    await this.doLoad(false);
  }

  /** 重新换票：失效跨域就绪标记（JWT 过期重走 SSO），换票后轮询重读令牌 */
  private async rebindToken(): Promise<boolean> {
    if (CrossDomainSession.isReady(DOMAIN_LIBSP.key)) {
      CrossDomainSession.invalidate(DOMAIN_LIBSP.key);
    }
    this.phase = 'bootstrap';
    const ok: boolean = await CrossDomainSession.ensure(DOMAIN_LIBSP);
    if (!ok) {
      return false;
    }
    return this.bindTokenWithRetry();
  }

  /** 轮询重读令牌：前端写 cookie 滞后于 onPageEnd，间隔重试 */
  private async bindTokenWithRetry(): Promise<boolean> {
    for (let attempt = 0; attempt < TOKEN_RETRY_COUNT; attempt++) {
      if (LibraryRepository.bindTokenFromCookie()) {
        return true;
      }
      await LibraryIndex.delay(TOKEN_RETRY_INTERVAL_MS);
    }
    return false;
  }

  private static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: (value: void) => void) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  /** 业务拉取：在借列表 + 借阅历史；会话失效自动重换票重试一次 */
  private async doLoad(retried: boolean): Promise<void> {
    this.phase = 'loading';
    try {
      const loans: LoanPage = await LibraryRepository.fetchLoans();
      const history: LoanPage = await LibraryRepository.fetchHistory();
      this.loans = loans;
      this.history = history;
      // 图书馆实时数量回写首页统计（ehall 聚合值为缓存，两处保持一致）
      EhallRepository.updateLoanCount(loans.numFound);
      this.phase = 'loaded';
    } catch (error) {
      const message: string = `${error}`;
      if (message.indexOf(LIBSP_SESSION_INVALID) >= 0 && !retried) {
        LibraryRepository.clearToken();
        const bound: boolean = await this.rebindToken();
        if (bound) {
          await this.doLoad(true);
          return;
        }
      }
      this.phase = 'error';
      this.errorText = message.indexOf(LIBSP_SESSION_INVALID) >= 0 ?
        '图书馆登录状态已失效，请重新进入本页重试' : plainError(message);
    }
  }

  /** 续借：传 loanId（非 recordId）；成功后刷新在借列表（应还日期/续借次数变化） */
  private async doRenew(record: LoanRecord): Promise<void> {
    if (this.renewingLoanId !== 0 || this.phase !== 'loaded') {
      return;
    }
    this.renewingLoanId = record.loanId;
    try {
      const result: RenewResult = await LibraryRepository.renewLoan([record.loanId]);
      if (result.failCount > 0) {
        const keys: string[] = Object.keys(result.failReasons);
        const reason: string = keys.length > 0 ? result.failReasons[keys[0]] : '';
        this.showToast(reason.length > 0 ? '续借失败：' + reason : '续借失败，请稍后重试');
      } else {
        this.showToast('已续借《' + record.title + '》');
      }
      const loans: LoanPage = await LibraryRepository.fetchLoans();
      this.loans = loans;
      EhallRepository.updateLoanCount(loans.numFound);
    } catch (error) {
      const message: string = `${error}`;
      if (message.indexOf(LIBSP_SESSION_INVALID) >= 0) {
        LibraryRepository.clearToken();
      }
      this.showToast('续借失败，请稍后重试');
    }
    this.renewingLoanId = 0;
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
    } catch (error) {
      // 弹出失败不中断流程
    }
  }

  private goBack(): void {
    this.getUIContext().getRouter().back();
  }

  /** 顶带副标题：阶段/统计（获取失败由页面内错误卡片反馈，顶带不显示红字） */
  private bandSubtitle(): string {
    if (this.phase === 'bootstrap') {
      return '正在建立图书馆会话…';
    }
    if (this.phase === 'loading') {
      return '正在获取借阅数据…';
    }
    if (this.phase === 'loaded') {
      return '已借' + this.loans.numFound + '本 · 还可借' + this.loans.loanNum + '本';
    }
    return '图书借阅';
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Scroll() {
        Column() {
          if (this.phase === 'loaded') {
            LibraryLoansCard({
              page: this.loans,
              renewingLoanId: this.renewingLoanId,
              onRenew: (record: LoanRecord): void => {
                this.doRenew(record);
              }
            })
            LibraryHistoryCard({ page: this.history })
            Text('数据来自图书馆系统（汇文 LibSP），续借结果以图书馆系统为准')
              .fontSize(12)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .padding({ top: 12, bottom: 12 })
              .transition(TransitionEffect.OPACITY
                .animation({ duration: 360, curve: Curve.EaseOut, delay: 180 }))
          } else if (this.phase === 'bootstrap' || this.phase === 'loading') {
            LibraryLoadingCard(this.phase === 'bootstrap' ? '正在建立图书馆会话…' : '正在获取借阅数据…')
          } else if (this.phase === 'error') {
            LibraryErrorCard(this.errorText, (): void => {
              this.start();
            })
          }
        }
        .padding({
          left: 16,
          right: 16,
          top: frostTopInsetVp(this.safeTopPx, this.getUIContext()),
          bottom: 88
        })
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ minWidth: '100%' })
      }
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .align(Alignment.Top)
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)

      FrostBand() {
        Row() {
          BackButton({
            onBack: () => {
              this.goBack();
            }
          })
          Text('图书借阅')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
            .layoutWeight(1)
          Text(this.bandSubtitle())
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '42%' })
        }
        .width('100%')
        .height(FROST_BAND_HEIGHT)
        .padding({ left: 8, right: 16 })
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
