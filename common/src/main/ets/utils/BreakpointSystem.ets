import { mediaquery } from '@kit.ArkUI';
import { commonConstants } from '../constants/CommonConstants';

declare interface BreakPointTypeOption<T> extends Record<string, T | undefined> {
  sm?: T;
  md?: T;
  lg?: T;
  xl?: T;
  xxl?: T;
}

export class BreakPointType<T> {
  options: BreakPointTypeOption<T>;

  constructor(option: BreakPointTypeOption<T>) {
    this.options = option;
  }

  getValue(currentBreakPoint: string): T {
    return this.options[currentBreakPoint] as T;
  }
}

class Breakpoint {
  name: string = '';
  size: number = 0;
  mediaQueryListener?: mediaquery.MediaQueryListener;
}

export class BreakpointSystem {
  private currentBreakpoint: string = commonConstants.breakpointsInitializeName;
  private readonly breakpointId: string = commonConstants.breakpointIdInitializeName;
  private readonly breakpoints: Breakpoint[] = [
    { name: commonConstants.breakpointsSmName, size: commonConstants.breakpointsSmSize },
    { name: commonConstants.breakpointsMdName, size: commonConstants.breakpointsMdSize },
    { name: commonConstants.breakpointsLgName, size: commonConstants.breakpointsLgSize },
    { name: commonConstants.breakpointsXlName, size: commonConstants.breakpointsXlSize }
  ];

  constructor(breakpointId: string) {
    this.breakpointId = breakpointId;
  }

  public register(uiContext: UIContext): void {
    this.breakpoints.forEach((breakpoint: Breakpoint, index: number) => {
      let condition: string = '';
      if (index === this.breakpoints.length - 1) {
        condition = `(${breakpoint.size}vp<=width)`;
      } else {
        condition = `(${breakpoint.size}vp<=width<${this.breakpoints[index + 1].size}vp)`;
      }

      breakpoint.mediaQueryListener = uiContext.getMediaQuery().matchMediaSync(condition);
      // 启动时立即按当前窗口宽度初始化断点：宽屏/横屏启动时媒体查询条件自注册起就满足，
      // 不会触发 change 事件，必须主动查询 matches，否则断点停留初始值（竖屏排版）。
      if (breakpoint.mediaQueryListener.matches) {
        this.updateCurrentBreakpoint(breakpoint.name);
      }
      breakpoint.mediaQueryListener.on('change', (mediaQueryResult: mediaquery.MediaQueryResult) => {
        if (mediaQueryResult.matches) {
          this.updateCurrentBreakpoint(breakpoint.name);
        }
      });
    });
  }

  public unregister(): void {
    this.breakpoints.forEach((breakpoint: Breakpoint) => {
      breakpoint.mediaQueryListener?.off('change');
    });
  }

  private updateCurrentBreakpoint(breakpoint: string): void {
    if (this.currentBreakpoint !== breakpoint) {
      this.currentBreakpoint = breakpoint;
      // setOrCreate：aboutToAppear 阶段注册即初始化时，AppStorage 中可能尚无该键
      // （视图组件的 @StorageLink 还未创建），set 对不存在的键会静默失败。
      AppStorage.setOrCreate<string>(this.breakpointId, this.currentBreakpoint);
    }
  }
}