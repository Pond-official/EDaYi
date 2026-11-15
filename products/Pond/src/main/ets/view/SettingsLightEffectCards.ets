/**
 * 开发者选项-底栏光效自定义卡（自 SettingsView 拆出）：
 * 预设色板选取底栏按压光效颜色，档位选择 HDS 沉浸材质等级；
 * 选择立即写入 AppStorage 并持久化，底栏实时生效。
 */
import { LengthMetrics } from '@kit.ArkUI';
import { GRADE_GOOD_BG, GRADE_GOOD_TEXT, TAG_DEFAULT_BG } from '../theme/AppColors';

/** 光效颜色预设（#RRGGBB 十六进制串） */
export class LightEffectPresets {
  /** 预设色板：白/淡蓝/系统蓝/青/紫/粉/橙/绿 */
  static readonly COLORS: string[] = [
    '#FFFFFF', '#87C8FF', '#007DFF', '#40C4FF',
    '#7C4DFF', '#FF80AB', '#FFB74D', '#69F0AE'
  ];
  /** 材质档位（与 hdsMaterial.MaterialLevel 一一对应） */
  static readonly LEVELS: string[] = ['ADAPTIVE', 'EXQUISITE', 'GENTLE', 'SMOOTH'];

  /** 材质档位显示名 */
  static levelLabel(level: string): string {
    if (level === 'EXQUISITE') {
      return '精致';
    }
    if (level === 'GENTLE') {
      return '轻柔';
    }
    if (level === 'SMOOTH') {
      return '流畅';
    }
    return '自适应';
  }
}

/** 光效自定义卡入参（单参对象字面量按引用传递，色板/档位随状态刷新） */
export interface SettingsLightEffectCardParams {
  color: string;
  level: string;
  onColorPick: (color: string) => void;
  onLevelPick: (level: string) => void;
}

/** 光效自定义卡：预设色板 + 材质档位，点击立即生效 */
@Builder
export function SettingsLightEffectCard(params: SettingsLightEffectCardParams) {
  Column({ space: 12 }) {
    Text('底栏光效')
      .fontSize(13)
      .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      .width('100%')

    Text('自定义底部悬浮栏按压光效颜色与材质档位，需设备支持沉浸光感（真机可见，模拟器渲染受限）')
      .fontSize(11)
      .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      .width('100%')

    Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(12), cross: LengthMetrics.vp(12) } }) {
      ForEach(LightEffectPresets.COLORS, (preset: string) => {
        Circle({ width: 28, height: 28 })
          .fill(preset)
          .stroke(params.color.toUpperCase() === preset.toUpperCase()
            ? $r('sys.color.ohos_id_color_text_primary_activated') : Color.Transparent)
          .strokeWidth(2.5)
          .onClick(() => {
            params.onColorPick(preset);
          })
      }, (preset: string) => preset)
    }
    .width('100%')

    Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
      ForEach(LightEffectPresets.LEVELS, (level: string) => {
        Text(LightEffectPresets.levelLabel(level))
          .fontSize(13)
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .borderRadius(16)
          .fontColor(params.level === level ? GRADE_GOOD_TEXT : $r('sys.color.ohos_id_color_text_secondary'))
          .backgroundColor(params.level === level ? GRADE_GOOD_BG : TAG_DEFAULT_BG)
          .onClick(() => {
            params.onLevelPick(level);
          })
      }, (level: string) => level)
    }
    .width('100%')

    Text(`当前：${params.color} · ${LightEffectPresets.levelLabel(params.level)}`)
      .fontSize(11)
      .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      .width('100%')
  }
  .width('100%')
  .alignItems(HorizontalAlign.Start)
  .padding(16)
  .borderRadius(16)
  .backgroundColor($r('app.color.card_background'))
}
