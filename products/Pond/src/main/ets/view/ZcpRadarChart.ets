/**
 * 综评素质得分多维图（雷达图）：
 * 各二级素质维度按「得分/满分」归一化为 0~1 半径绘制数据多边形，
 * 网格为 25%/50%/75%/100% 同心多边形加中心辐射轴线；
 * 维度标签沿轴向居中排布在轴顶点外侧，颜色跟随系统深浅色资源。
 * 注意：Path commands 坐标单位为 px（ArkUI 规范），几何计算基于 vp，
 * 生成命令字符串时必须经 vp2px 按屏幕密度换算，否则图形会缩小挂在组件左上角。
 */

/** 少于 3 个有效维度时雷达图无意义，调用方不展示 */
const MIN_AXES: number = 3;
/** 环半径外预留边距（vp），容纳维度名与「得分/满分」标签 */
const CHART_MARGIN: number = 58;
/** 轴顶点到标签中心的径向间距（vp） */
const LABEL_GAP: number = 28;
/** 维度名标签最大宽度（vp），超长折行为两行 */
const LABEL_MAX_WIDTH: number = 56;
/** 宽屏下绘图区最大边长（vp） */
const CHART_MAX_SIZE: number = 420;

/** 雷达图单轴数据（一级素质维度归一化条目） */
export class RadarEntry {
  /** 维度名称（一级指标名） */
  name: string = '';
  /** 得分展示文本 */
  scoreText: string = '';
  /** 满分展示文本 */
  capText: string = '';
  /** 归一化得分（0~1，得分/满分并裁剪） */
  value: number = 0;
}

@Component
export struct ZcpRadarChart {
  /** 雷达轴数据（由调用方保证 ≥ MIN_AXES 条有效维度） */
  @Prop entries: RadarEntry[] = [];
  /** 绘图区边长（vp，onAreaChange 实测宽高） */
  @State chartSize: number = 0;

  private axisCount(): number {
    return this.entries.length;
  }

  /** 轴角度（弧度）：0 号轴朝正上，其余顺时针均分 */
  private axisAngle(index: number): number {
    return -Math.PI / 2 + index * 2 * Math.PI / this.axisCount();
  }

  /** 基准半径（100% 环，vp） */
  private baseRadius(): number {
    return this.chartSize / 2 - CHART_MARGIN;
  }

  private vertexX(radius: number, angle: number): number {
    return this.chartSize / 2 + radius * Math.cos(angle);
  }

  private vertexY(radius: number, angle: number): number {
    return this.chartSize / 2 + radius * Math.sin(angle);
  }

  /** Path commands 坐标单位为 px，几何值基于 vp，需按屏幕密度换算 */
  private toPx(value: number): number {
    return this.getUIContext().vp2px(value);
  }

  /** 网格路径：25/50/75/100% 同心多边形 + 中心到各轴顶点的轴线（commands 单位 px） */
  private gridCommands(): string {
    const levels: number[] = [0.25, 0.5, 0.75, 1];
    let cmd: string = '';
    for (const factor of levels) {
      for (let i = 0; i < this.axisCount(); i++) {
        const angle: number = this.axisAngle(i);
        const x: number = this.toPx(this.vertexX(this.baseRadius() * factor, angle));
        const y: number = this.toPx(this.vertexY(this.baseRadius() * factor, angle));
        cmd += i === 0 ? `M${x.toFixed(2)} ${y.toFixed(2)}` : ` L${x.toFixed(2)} ${y.toFixed(2)}`;
      }
      cmd += ' Z';
    }
    for (let i = 0; i < this.axisCount(); i++) {
      const angle: number = this.axisAngle(i);
      cmd += ` M${this.toPx(this.chartSize / 2).toFixed(2)} ${this.toPx(this.chartSize / 2).toFixed(2)}` +
        ` L${this.toPx(this.vertexX(this.baseRadius(), angle)).toFixed(2)}` +
        ` ${this.toPx(this.vertexY(this.baseRadius(), angle)).toFixed(2)}`;
    }
    return cmd;
  }

  /** 数据多边形路径：各维度按归一化得分取半径（commands 单位 px） */
  private dataCommands(): string {
    let cmd: string = '';
    for (let i = 0; i < this.axisCount(); i++) {
      const angle: number = this.axisAngle(i);
      const radius: number = this.baseRadius() * this.entries[i].value;
      const x: number = this.toPx(this.vertexX(radius, angle));
      const y: number = this.toPx(this.vertexY(radius, angle));
      cmd += i === 0 ? `M${x.toFixed(2)} ${y.toFixed(2)}` : ` L${x.toFixed(2)} ${y.toFixed(2)}`;
    }
    return cmd + ' Z';
  }

  /** 数据顶点圆点位置（圆点 8vp，锚点居中补偿） */
  private vertexPosition(index: number): Position {
    const angle: number = this.axisAngle(index);
    const radius: number = this.baseRadius() * this.entries[index].value;
    const pos: Position = {
      x: this.vertexX(radius, angle) - 4,
      y: this.vertexY(radius, angle) - 4
    };
    return pos;
  }

  /** 维度标签锚点位置（轴顶点外 LABEL_GAP） */
  private labelPosition(index: number): Position {
    const angle: number = this.axisAngle(index);
    const radius: number = this.baseRadius() + LABEL_GAP;
    const pos: Position = {
      x: this.vertexX(radius, angle),
      y: this.vertexY(radius, angle)
    };
    return pos;
  }

  /** 标签数值文本：「得分 / 满分」 */
  private valueText(entry: RadarEntry): string {
    return entry.scoreText + ' / ' + entry.capText;
  }

  /** Area 尺寸转 vp 数值（数字直接取值，带单位字符串去单位解析） */
  private lengthToVp(value: Length): number {
    if (typeof value === 'number') {
      return value;
    }
    const text: string = `${value}`.replace('vp', '').replace('%', '');
    const parsed: number = Number.parseFloat(text);
    return Number.isNaN(parsed) ? 0 : parsed;
  }

  build() {
    Stack() {
      if (this.chartSize > 0 && this.entries.length >= MIN_AXES) {
        Path()
          .width(this.chartSize)
          .height(this.chartSize)
          .commands(this.gridCommands())
          .fillOpacity(0)
          .stroke($r('sys.color.ohos_id_color_list_separator'))
          .strokeWidth(1)
        Path()
          .width(this.chartSize)
          .height(this.chartSize)
          .commands(this.dataCommands())
          .fill($r('sys.color.ohos_id_color_text_primary_activated'))
          .fillOpacity(0.15)
          .stroke($r('sys.color.ohos_id_color_text_primary_activated'))
          .strokeWidth(2)
          .strokeLineJoin(LineJoinStyle.Round)
        ForEach(this.entries, (entry: RadarEntry, index: number) => {
          Circle({ width: 8, height: 8 })
            .fill($r('sys.color.ohos_id_color_text_primary_activated'))
            .position(this.vertexPosition(index))
        }, (entry: RadarEntry, index: number) => 'dot:' + entry.name + ':' + entry.scoreText + ':' + entry.capText)
        ForEach(this.entries, (entry: RadarEntry, index: number) => {
          Column({ space: 2 }) {
            Text(entry.name)
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.ohos_id_color_text_primary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Center)
              .constraintSize({ maxWidth: LABEL_MAX_WIDTH })
            Text(this.valueText(entry))
              .fontSize(10)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('sys.color.ohos_id_color_text_primary_activated'))
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Center)
          .position(this.labelPosition(index))
          .markAnchor({ x: '50%', y: '50%' })
        }, (entry: RadarEntry, index: number) => 'label:' + entry.name + ':' + entry.scoreText + ':' + entry.capText)
      }
    }
    .width('100%')
    .constraintSize({ maxWidth: CHART_MAX_SIZE })
    .aspectRatio(1)
    .alignSelf(ItemAlign.Center)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.chartSize = this.lengthToVp(newArea.width);
    })
  }
}
