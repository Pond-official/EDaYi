import { notificationManager } from '@kit.NotificationKit';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { calendarManager } from '@kit.CalendarKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ScheduleCellInfo, TermStatus } from '../model/JwModels';

const TAG: string = 'ReminderScheduler';
const DOMAIN: number = 0x0000;
/** 旧版（日历方案）专属日历账户名，用于升级后一次性清理 */
const LEGACY_CALENDAR_NAME: string = 'com.example.edaiyi_next.schedule';
/** 设置页测试通知使用的通知 id */
const TEST_NOTIFICATION_ID: number = 999999;
/** 设置页测试代理提醒使用的通知 id */
const TEST_AGENT_NOTIFICATION_ID: number = 999998;
/** 单应用有效代理提醒上限（API26 为 64），预留余量后取 60 */
const MAX_AGENT_REMINDERS: number = 60;
/** 本应用包名与入口 Ability（点击提醒通知后跳转） */
const APP_PKG_NAME: string = 'com.example.edaiyi_next';
const APP_ABILITY_NAME: string = 'PondAbility';

/** 一次待提醒的上课时间点（提前 N 分钟触发通知） */
class ClassOccurrence {
  fireAt: number = 0;
  startTimeText: string = '';
  courseName: string = '';
  location: string = '';
}

/**
 * 上课提醒调度器（后台代理提醒方案）：
 * 读取用户设置（开关 + 提前分钟数），为本周/下周课表内尚未到提醒时间的
 * 每节课向系统发布一条后台代理提醒（reminderAgentManager 倒计时类型），
 * 应用退到后台、退出或进程被清理后由系统服务代理，到点经
 * Notification Kit 弹出系统通知（SOCIAL_COMMUNICATION 通道）。
 * 代理提醒发布失败（未开通权益/超出数量上限等）时降级为应用内定时器，
 * 应用存活期间仍可提醒。数据同步、应用启动（含离线缓存回显）与设置
 * 变更时重建。另含旧版日历方案的一次性清理：删除"e大医课表"日历账户及其日程，
 * 无权限或无该账户时静默跳过。
 */
export class ReminderScheduler {
  private static timerIds: number[] = [];
  private static legacyCleaned: boolean = false;

  static async schedule(cells: ScheduleCellInfo[], term: TermStatus,
    context: common.UIAbilityContext | null): Promise<void> {
    await ReminderScheduler.cleanupLegacyCalendar(context);
    ReminderScheduler.clearTimers();
    await ReminderScheduler.cancelCourseReminders();
    const enabled: boolean = AppStorage.get<boolean>('jwReminderEnabled') ?? true;
    const advance: number = AppStorage.get<number>('jwReminderAdvance') ?? 10;
    if (!enabled) {
      AppStorage.setOrCreate('jwNextReminder', '');
      hilog.info(DOMAIN, TAG, 'reminder disabled by settings');
      return;
    }
    await ReminderScheduler.ensureNotificationEnabled(context);
    const occurrences: ClassOccurrence[] = ReminderScheduler.upcomingOccurrences(cells, term, advance);
    const targets: ClassOccurrence[] = occurrences.slice(0, MAX_AGENT_REMINDERS);
    let agentCount: number = 0;
    let inAppCount: number = 0;
    let agentAvailable: boolean = true;
    for (const occurrence of targets) {
      const delay: number = occurrence.fireAt - Date.now();
      if (delay <= 0) {
        continue;
      }
      if (agentAvailable) {
        try {
          await ReminderScheduler.publishAgentReminder(occurrence, advance);
          agentCount++;
          continue;
        } catch (error) {
          // 代理提醒不可用（未开通权益/超出数量上限），后续全部降级为应用内定时器
          agentAvailable = false;
          const err: BusinessError = error as BusinessError;
          hilog.error(DOMAIN, TAG, 'agent reminder publish failed: code=%{public}s msg=%{public}s',
            `${err.code}`, `${err.message}`);
        }
      }
      const notifyId: number = Math.floor(occurrence.fireAt / 60000) % 65536;
      const timerId: number = setTimeout(() => {
        ReminderScheduler.publish(notifyId, occurrence, advance);
      }, delay);
      ReminderScheduler.timerIds.push(timerId);
      inAppCount++;
    }
    if (occurrences.length > 0) {
      AppStorage.setOrCreate('jwNextReminder', ReminderScheduler.formatNext(occurrences[0]));
    } else {
      AppStorage.setOrCreate('jwNextReminder', '');
    }
    hilog.info(DOMAIN, TAG,
      'reminders armed: agent=%{public}d inApp=%{public}d advance=%{public}d upcoming=%{public}d',
      agentCount, inAppCount, advance, occurrences.length);
  }

  /**
   * 发布一条测试通知（设置页验证通知链路用）：
   * 立即发送一条通知验证通知渠道，另发布一条 60 秒倒计时代理提醒，
   * 用于验证应用退出后的后台代理提醒链路。
   */
  static async publishTest(context: common.UIAbilityContext | null): Promise<void> {
    try {
      await ReminderScheduler.ensureNotificationEnabled(context);
      const request: notificationManager.NotificationRequest = {
        id: TEST_NOTIFICATION_ID,
        notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: '上课提醒',
            text: '这是一条测试通知，提醒功能工作正常',
            additionalText: '60秒后将送达一条测试代理提醒'
          }
        }
      };
      await notificationManager.publish(request);
      hilog.info(DOMAIN, TAG, 'test notification published');
      try {
        const agentTest: reminderAgentManager.ReminderRequestTimer = {
          reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_TIMER,
          triggerTimeInSeconds: 60,
          title: '上课提醒',
          content: '测试代理提醒：应用退出或被清理后，此类提醒仍会准时送达',
          notificationId: TEST_AGENT_NOTIFICATION_ID,
          slotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
          wantAgent: {
            pkgName: APP_PKG_NAME,
            abilityName: APP_ABILITY_NAME
          }
        };
        await reminderAgentManager.publishReminder(agentTest);
        hilog.info(DOMAIN, TAG, 'test agent reminder published, fires in 60s');
      } catch (error) {
        const err: BusinessError = error as BusinessError;
        hilog.error(DOMAIN, TAG, 'test agent reminder failed: code=%{public}s msg=%{public}s',
          `${err.code}`, `${err.message}`);
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'publishTest failed: %{public}s', `${error}`);
    }
  }

  /** 取消全部上课提醒（后台代理提醒与应用内降级定时器），严格隐私模式清理时调用 */
  static async cancelAll(): Promise<void> {
    ReminderScheduler.clearTimers();
    await ReminderScheduler.cancelAgentReminders();
  }

  /** 发布单条后台代理提醒（倒计时类型，到点由系统服务代理弹出通知） */
  private static async publishAgentReminder(occurrence: ClassOccurrence, advance: number): Promise<number> {
    let content: string = occurrence.startTimeText + ' ' + occurrence.courseName;
    if (occurrence.location.length > 0) {
      content += '，地点：' + occurrence.location;
    }
    const request: reminderAgentManager.ReminderRequestTimer = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_TIMER,
      triggerTimeInSeconds: Math.max(1, Math.ceil((occurrence.fireAt - Date.now()) / 1000)),
      title: '上课提醒 · 还有' + advance + '分钟',
      content: content,
      notificationId: Math.floor(occurrence.fireAt / 60000) % 65536,
      slotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
      wantAgent: {
        pkgName: APP_PKG_NAME,
        abilityName: APP_ABILITY_NAME
      }
    };
    return reminderAgentManager.publishReminder(request);
  }

  /** 取消当前应用已发布的全部后台代理提醒 */
  private static async cancelAgentReminders(): Promise<void> {
    try {
      await reminderAgentManager.cancelAllReminders();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'cancelAgentReminders failed: %{public}s', `${error}`);
    }
  }

  /**
   * 仅取消课程类后台代理提醒，保留测试代理提醒（notificationId 999998）：
   * 数据同步/设置变更重建提醒时不误杀 60 秒测试链路。
   * 逐条按 reminderId 取消，同时覆盖应用重启后无法追踪的历史课程提醒。
   */
  private static async cancelCourseReminders(): Promise<void> {
    try {
      const infos: reminderAgentManager.ReminderInfo[] =
        await reminderAgentManager.getAllValidReminders();
      for (const info of infos) {
        if (info.reminderReq.notificationId === TEST_AGENT_NOTIFICATION_ID) {
          continue;
        }
        try {
          await reminderAgentManager.cancelReminder(info.reminderId);
        } catch (error) {
          hilog.error(DOMAIN, TAG, 'cancelReminder failed: id=%{public}d %{public}s',
            info.reminderId, `${error}`);
        }
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'cancelCourseReminders failed: %{public}s', `${error}`);
    }
  }

  /** 清空全部在途的应用内降级提醒定时器 */
  private static clearTimers(): void {
    for (const timerId of ReminderScheduler.timerIds) {
      clearTimeout(timerId);
    }
    ReminderScheduler.timerIds = [];
  }

  /** 通知开关未授权时经 UIAbilityContext 弹窗申请 */
  private static async ensureNotificationEnabled(context: common.UIAbilityContext | null): Promise<void> {
    try {
      const enabled: boolean = await notificationManager.isNotificationEnabled();
      if (enabled) {
        return;
      }
      if (context === null) {
        hilog.error(DOMAIN, TAG, 'notification disabled and no UIAbilityContext, skip request');
        return;
      }
      await notificationManager.requestEnableNotification(context);
      hilog.info(DOMAIN, TAG, 'requestEnableNotification done');
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'ensureNotificationEnabled failed: %{public}s', `${error}`);
    }
  }

  /** 到点发布上课提醒通知（应用内降级定时器回调） */
  private static publish(notifyId: number, occurrence: ClassOccurrence, advance: number): void {
    let text: string = occurrence.startTimeText + ' ' + occurrence.courseName;
    if (occurrence.location.length > 0) {
      text += '，地点：' + occurrence.location;
    }
    const request: notificationManager.NotificationRequest = {
      id: notifyId,
      notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: '上课提醒',
          text: text,
          additionalText: '还有' + advance + '分钟上课'
        }
      }
    };
    notificationManager.publish(request)
      .then(() => {
        hilog.info(DOMAIN, TAG, 'notification published: %{public}d %{public}s',
          notifyId, occurrence.courseName);
      })
      .catch((error: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'publish failed: code=%{public}s msg=%{public}s',
          `${error.code}`, `${error.message}`);
      });
  }

  /**
   * 旧版日历提醒的一次性清理：删除"e大医课表"日历账户及全部日程，
   * 避免升级后残留的日历提醒继续触发。未授权日历权限或账户不存在时静默跳过。
   */
  private static async cleanupLegacyCalendar(context: common.UIAbilityContext | null): Promise<void> {
    if (ReminderScheduler.legacyCleaned) {
      return;
    }
    ReminderScheduler.legacyCleaned = true;
    if (context === null) {
      return;
    }
    try {
      const manager: calendarManager.CalendarManager = calendarManager.getCalendarManager(context);
      const account: calendarManager.CalendarAccount = {
        name: LEGACY_CALENDAR_NAME,
        type: calendarManager.CalendarType.LOCAL,
        displayName: 'e大医课表'
      };
      const calendar: calendarManager.Calendar = await manager.getCalendar(account);
      await manager.deleteCalendar(calendar);
      hilog.info(DOMAIN, TAG, 'legacy calendar deleted');
    } catch (error) {
      hilog.info(DOMAIN, TAG, 'legacy calendar cleanup skipped: %{public}s', `${error}`);
    }
  }

  /**
   * 计算本周/下周内提醒时间未过的所有上课时间点。
   * 本周一为锚点，周次按 TermStatus.currentWeek 推算；周位图过滤生效。
   */
  private static upcomingOccurrences(cells: ScheduleCellInfo[], term: TermStatus,
    advanceMinutes: number): ClassOccurrence[] {
    const now: Date = new Date();
    const nowMs: number = now.getTime();
    const todayNum: number = now.getDay() === 0 ? 7 : now.getDay();
    const monday: Date = new Date(now.getFullYear(), now.getMonth(), now.getDate() - (todayNum - 1));
    const currentWeek: number = term.currentWeek;
    const disabledCourses: string[] = AppStorage.get<string[]>('jwReminderDisabledCourses') ?? [];
    const occurrences: ClassOccurrence[] = [];
    for (const cell of cells) {
      if (disabledCourses.indexOf(cell.courseName) >= 0) {
        continue;
      }
      const start: number[] | null = ReminderScheduler.parseTime(cell.startTime);
      if (start === null) {
        continue;
      }
      const weekOffsets: number[] = currentWeek > 0 ? [0, 1] : [0];
      for (const offset of weekOffsets) {
        const week: number = currentWeek + offset;
        if (!cell.activeInWeek(week)) {
          continue;
        }
        const dayDate: Date = new Date(
          monday.getFullYear(), monday.getMonth(),
          monday.getDate() + offset * 7 + (cell.dayOfWeek - 1));
        const classStart: Date = new Date(
          dayDate.getFullYear(), dayDate.getMonth(), dayDate.getDate(),
          start[0], start[1], 0);
        const fireAt: number = classStart.getTime() - advanceMinutes * 60 * 1000;
        if (fireAt <= nowMs) {
          continue;
        }
        const occurrence: ClassOccurrence = new ClassOccurrence();
        occurrence.fireAt = fireAt;
        occurrence.startTimeText = cell.startTime;
        occurrence.courseName = cell.courseName;
        occurrence.location = cell.location;
        occurrences.push(occurrence);
      }
    }
    occurrences.sort((a: ClassOccurrence, b: ClassOccurrence): number => a.fireAt - b.fireAt);
    return occurrences;
  }

  /** 格式化"下次提醒"文案：如 "10月24日 08:20 · 中药鉴别、开发与转化" */
  private static formatNext(occurrence: ClassOccurrence): string {
    const date: Date = new Date(occurrence.fireAt);
    return (date.getMonth() + 1) + '月' + date.getDate() + '日 ' +
      ReminderScheduler.pad(date.getHours()) + ':' + ReminderScheduler.pad(date.getMinutes()) +
      ' · ' + occurrence.courseName;
  }

  private static pad(value: number): string {
    return value < 10 ? '0' + `${value}` : `${value}`;
  }

  /**
   * 解析形如 "8:30" 的时间，非法返回 null。
   */
  private static parseTime(time: string): number[] | null {
    if (time.length === 0) {
      return null;
    }
    const parts: string[] = time.split(':');
    if (parts.length < 2) {
      return null;
    }
    const hour: number = Number(parts[0]);
    const minute: number = Number(parts[1]);
    if (Number.isNaN(hour) || Number.isNaN(minute)) {
      return null;
    }
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return null;
    }
    return [hour, minute];
  }
}
