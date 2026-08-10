/// 输入相关的平台差异判断。
///
/// 移动端与桌面端在「自动聚焦」上的取舍相反：桌面端聚焦只是把光标放进输入框，
/// 用户可以直接键入，代价为零；移动端聚焦会连带顶起软键盘，遮住半屏内容，
/// 用户还没看清表单就得先收键盘。因此凡是自动聚焦都应经由 [kAutoFocusOnOpen]
/// 判断，把「打开即聚焦」限制在桌面端，移动端一律等用户主动点输入框。
library;

import 'package:flutter/foundation.dart';

/// 当前是否为移动平台（Android / iOS）
bool get isMobileInputPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// 打开表单 / 弹窗时是否自动聚焦首个输入框。
///
/// 移动端为 false：避免自动弹出软键盘（见 library 注释）。
bool get kAutoFocusOnOpen => !isMobileInputPlatform;
