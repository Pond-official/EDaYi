import { fileUri } from '@kit.CoreFileKit';

/**
 * 背景图片渲染工具：
 * Image/backgroundImage 不能直接加载应用沙箱路径（'file://' + 路径 拼接的非法 URI 静默失败），
 * 必须传入应用沙箱 URI（file://<bundleName>/<沙箱路径>），由 fileUri.getUriFromPath 生成并转义特殊字符。
 * 本应用持久化与 AppStorage 中保存原始沙箱路径（便于 fs 存在性校验与文件清理），渲染前经此处转换。
 */
export class BackgroundUtils {
  /** 沙箱路径转应用沙箱 URI（空串原样返回，转换失败返回空串避免渲染异常） */
  static imageSrcOf(path: string): string {
    if (path.length === 0) {
      return '';
    }
    try {
      return fileUri.getUriFromPath(path);
    } catch (error) {
      return '';
    }
  }
}
