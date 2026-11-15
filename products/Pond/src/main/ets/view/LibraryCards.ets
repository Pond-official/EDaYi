import { LoanPage, LoanRecord } from '../model/LibraryModels';

/** 图书借阅详情页卡片集（当前借阅/借阅历史两段） */

/** 当前借阅卡入参（单参对象字面量按引用传递，续借状态随 renewingLoanId 刷新） */
export interface LibraryLoansCardParams {
  page: LoanPage;
  /** 正在续借的 loanId（0 = 无在途续借） */
  renewingLoanId: number;
  onRenew: (record: LoanRecord) => void;
}

/** 当前借阅卡：头部统计（已借/剩余可借）+ 在借行（含续借按钮） */
@Builder
export function LibraryLoansCard(params: LibraryLoansCardParams) {
  Column() {
    Row() {
      Text('当前借阅')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
      Blank()
      Text('已借' + params.page.numFound + '本 · 还可借' + params.page.loanNum + '本')
        .fontSize(11)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
    }
    .width('100%')
    .padding({ bottom: 4 })
    if (params.page.records.length === 0) {
      Text('当前没有在借图书')
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .padding({ top: 14, bottom: 14 })
    } else {
      ForEach(params.page.records, (record: LoanRecord) => {
        LibraryLoanRow(record, params.renewingLoanId === record.loanId, (): void => {
          params.onRenew(record);
        })
      }, (record: LoanRecord) => 'loan' + record.loanId + ':' + record.normReturnDate
        + ':' + record.renewTimes + ':' + record.overdueDays)
    }
  }
  .width('100%')
  .alignItems(HorizontalAlign.Start)
  .padding(16)
  .borderRadius(16)
  .backgroundColor($r('app.color.card_background'))
}

/** 在借单行：书名/著者/借出与应还日期，右侧续借按钮（逾期标红提示） */
@Builder
function LibraryLoanRow(record: LoanRecord, renewing: boolean, onRenew: () => void) {
  Row() {
    Column({ space: 3 }) {
      Text(record.title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(record.author)
        .fontSize(11)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(record.isOverdue() ?
        '借出 ' + record.loanDate + ' · 应还 ' + record.normReturnDate + ' · 已逾期' + record.overdueDays + '天' :
        '借出 ' + record.loanDate + ' · 应还 ' + record.normReturnDate)
        .fontSize(11)
        .fontColor(record.isOverdue() ?
          $r('sys.color.ohos_id_color_warning') : $r('sys.color.ohos_id_color_text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)

    if (renewing) {
      LoadingProgress()
        .width(22)
        .height(22)
        .margin({ left: 10 })
        .color($r('sys.color.ohos_id_color_text_primary_activated'))
    } else {
      Button('续借')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .height(28)
        .borderRadius(14)
        .padding({ left: 14, right: 14 })
        .margin({ left: 10 })
        .buttonStyle(ButtonStyleMode.NORMAL)
        .onClick(() => {
          onRenew();
        })
    }
  }
  .width('100%')
  .alignItems(VerticalAlign.Center)
  .padding({ top: 8, bottom: 8 })
}

/** 借阅历史卡入参（单参对象字面量按引用传递） */
export interface LibraryHistoryCardParams {
  page: LoanPage;
}

/** 借阅历史卡：头部统计 + 历史行（借出/归还日期） */
@Builder
export function LibraryHistoryCard(params: LibraryHistoryCardParams) {
  Column() {
    Row() {
      Text('借阅历史')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
      Blank()
      Text('共' + params.page.numFound + '条')
        .fontSize(11)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
    }
    .width('100%')
    .padding({ bottom: 4 })
    if (params.page.records.length === 0) {
      Text('暂无借阅历史')
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .padding({ top: 14, bottom: 14 })
    } else {
      ForEach(params.page.records, (record: LoanRecord) => {
        LibraryHistoryRow(record)
      }, (record: LoanRecord) => 'history' + record.recordId + ':' + record.returnDate)
    }
  }
  .width('100%')
  .alignItems(HorizontalAlign.Start)
  .padding(16)
  .borderRadius(16)
  .backgroundColor($r('app.color.card_background'))
  .margin({ top: 16 })
}

/** 借阅历史单行：书名/著者·出版社/借出与归还日期 */
@Builder
function LibraryHistoryRow(record: LoanRecord) {
  Column({ space: 3 }) {
    Text(record.title)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.ohos_id_color_text_primary'))
      .maxLines(2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
    Text((record.author.length > 0 ? record.author : '未知著者')
      + (record.publisher.length > 0 ? ' · ' + record.publisher : ''))
      .fontSize(11)
      .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
    Text('借出 ' + record.loanDate + ' · '
      + (record.returnDate.length > 0 ? '归还 ' + record.returnDate : '未归还'))
      .fontSize(11)
      .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }
  .width('100%')
  .alignItems(HorizontalAlign.Start)
  .padding({ top: 8, bottom: 8 })
}

/** 图书借阅加载中卡片 */
@Builder
export function LibraryLoadingCard(text: string) {
  Column({ space: 12 }) {
    LoadingProgress()
      .width(36)
      .height(36)
      .color($r('sys.color.ohos_id_color_text_primary_activated'))
    Text(text)
      .fontSize(14)
      .fontColor($r('sys.color.ohos_id_color_text_secondary'))
  }
  .width('100%')
  .padding({ top: 48, bottom: 48 })
  .alignItems(HorizontalAlign.Center)
  .borderRadius(16)
  .backgroundColor($r('app.color.card_background'))
}

/** 图书借阅失败卡片（onRetry 重试） */
@Builder
export function LibraryErrorCard(errorText: string, onRetry: () => void) {
  Column({ space: 12 }) {
    SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
      .fontSize(36)
      .fontColor([$r('sys.color.ohos_id_color_warning')])
    Text(errorText)
      .fontSize(14)
      .fontColor($r('sys.color.ohos_id_color_text_primary'))
      .textAlign(TextAlign.Center)
    Text('重新获取')
      .fontSize(15)
      .fontWeight(FontWeight.Medium)
      .fontColor(Color.White)
      .padding({ left: 24, right: 24, top: 10, bottom: 10 })
      .borderRadius(20)
      .backgroundColor($r('sys.color.ohos_id_color_text_primary_activated'))
      .onClick(() => {
        onRetry();
      })
  }
  .width('100%')
  .padding({ left: 16, right: 16, top: 36, bottom: 36 })
  .alignItems(HorizontalAlign.Center)
  .borderRadius(16)
  .backgroundColor($r('app.color.card_background'))
}
