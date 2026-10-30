import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nfc_use/core/services/card_import_service.dart';
import 'package:nfc_use/core/services/nfc_service.dart';
import 'package:nfc_use/core/services/sqlite_service.dart';
import 'package:nfc_use/core/services/zip.dart';
import 'package:nfc_use/pages/Setting/setting_item.dart';

// File path: lib/pages/Setting/index.dart
// 设置页面：NFC 卡模拟状态、调试信息与卡片数据管理
class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  // ====== NFC 综合状态 ======
  bool _nfcHardwareAvailable = false;
  bool _hceSupported = false;
  bool _isDefaultService = false;
  bool _isEmulating = false;
  bool _isLoadingNfc = true;
  bool _isImportingCards = false;
  bool _showNfcDebugInfo = false;
  NfcDebugInfo _nfcDebugInfo = NfcDebugInfo.empty;
  Timer? _nfcDebugTimer;

  // ====== 生命周期 ======
  @override
  void initState() {
    super.initState();
    _initNfcState();
    _nfcDebugTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_showNfcDebugInfo) {
        _refreshNfcDebugInfo();
      }
    });
  }

  @override
  void dispose() {
    _nfcDebugTimer?.cancel();
    super.dispose();
  }

  // ====== NFC 综合检测（硬件 + HCE 支持 + 默认服务 + 当前模拟状态） ======
  Future<void> _refreshNfcState() async {
    setState(() => _isLoadingNfc = true);
    try {
      final hw = await NfcService.instance.isNfcAvailable();
      final hce = await NfcService.instance.isHceSupported();
      final def = await NfcService.instance.isDefaultPaymentApp();
      final emu = NfcService.instance.isEmulating;
      final debug = _showNfcDebugInfo
          ? await NfcService.instance.getHceDebugInfo()
          : _nfcDebugInfo;
      if (!mounted) return;
      setState(() {
        _nfcHardwareAvailable = hw;
        _hceSupported = hce;
        _isDefaultService = def;
        _isEmulating = emu;
        _nfcDebugInfo = debug;
        _isLoadingNfc = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingNfc = false);
    }
  }

  Future<void> _refreshNfcDebugInfo() async {
    final debug = await NfcService.instance.getHceDebugInfo();
    if (!mounted) return;
    setState(() => _nfcDebugInfo = debug);
  }

  /// NFC 功能综合正常：硬件可用 + HCE 支持
  bool get _nfcFunctionalOk => _nfcHardwareAvailable && _hceSupported;

  String get _nfcStatusText {
    if (_isLoadingNfc) return '检测中...';
    if (!_nfcHardwareAvailable) return 'NFC 硬件不可用（未开启或不支持）';
    if (!_hceSupported) return '设备不支持 HCE 卡模拟';
    if (_isEmulating) return '功能正常（卡模拟已启用）';
    if (!_isDefaultService) return '功能正常，但未设为默认付款应用';
    return '功能正常（待机中）';
  }

  Color get _nfcStatusColor {
    if (_isLoadingNfc) return Colors.grey;
    if (!_nfcHardwareAvailable || !_hceSupported) return Colors.redAccent;
    if (_isEmulating) return const Color(0xFF00966A);
    return Colors.orange;
  }

  IconData get _nfcStatusIcon {
    if (_isLoadingNfc) return Icons.hourglass_top;
    if (!_nfcHardwareAvailable || !_hceSupported) return Icons.error_outline;
    if (_isEmulating) return Icons.check_circle;
    return Icons.info_outline;
  }

  String get _nfcDebugUpdatedText {
    final updatedAt = _nfcDebugInfo.updatedAt;
    if (updatedAt == null) return '暂无更新时间';
    final hour = updatedAt.hour.toString().padLeft(2, '0');
    final minute = updatedAt.minute.toString().padLeft(2, '0');
    final second = updatedAt.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  String _compactDebugHex(String value) {
    if (value.isEmpty) return '暂无';
    if (value.length <= 48) return value;
    return '${value.substring(0, 48)}...';
  }

  List<Widget> _buildNfcDebugTiles() {
    return [
      StatusTile(
        icon: Icons.bug_report,
        title: '最近识别事件',
        subtitle: '${_nfcDebugInfo.lastEvent}（$_nfcDebugUpdatedText）',
        trailing: Icon(
          _nfcDebugInfo.apduCount > 0
              ? Icons.sensors
              : Icons.sensors_off_outlined,
          color: _nfcDebugInfo.apduCount > 0
              ? const Color(0xFF00966A)
              : Colors.grey,
        ),
      ),
      StatusTile(
        icon: Icons.confirmation_number,
        title: 'APDU 次数',
        subtitle: '${_nfcDebugInfo.apduCount} 次',
      ),
      StatusTile(
        icon: Icons.key,
        title: '当前响应 Token',
        subtitle: _nfcDebugInfo.token.isEmpty ? '暂无' : _nfcDebugInfo.token,
      ),
      StatusTile(
        icon: Icons.input,
        title: '最后 APDU',
        subtitle: _compactDebugHex(_nfcDebugInfo.lastApdu),
      ),
      StatusTile(
        icon: Icons.output,
        title: '最后响应',
        subtitle: _compactDebugHex(_nfcDebugInfo.lastResponse),
      ),
      ActionTile(
        icon: Icons.refresh,
        title: '刷新调试信息',
        subtitle: '手动读取最近一次 HCE 识别记录',
        onTap: _refreshNfcDebugInfo,
      ),
    ];
  }

  /// 首次进入设置页：检测状态并在功能可用时自动启用 HCE 卡模拟
  Future<void> _initNfcState() async {
    await _refreshNfcState();
    if (!_nfcFunctionalOk || _isEmulating) return;
    final r = await NfcService.instance.setEmulationEnabled(true);
    if (!r.isSuccess || !mounted) return;
    await _refreshNfcState();
  }

  /// 重新检测并启用卡模拟，并把结果显示给用户
  Future<void> _restartEmulation() async {
    await _refreshNfcState();
    if (!_nfcFunctionalOk) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('NFC 硬件或 HCE 不可用，无法启动')),
        );
      }
      return;
    }
    final r = await NfcService.instance.setEmulationEnabled(true);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(r.message)));
    await _refreshNfcState();
  }

  Future<void> _requestDefaultPaymentApp() async {
    final opened = await NfcService.instance.requestSetDefaultPaymentApp();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(opened ? '请在系统弹窗中确认设为默认付款应用' : '无法直接弹出授权窗口，已尝试打开 NFC 设置'),
      ),
    );
    Future.delayed(const Duration(seconds: 1), _refreshNfcState);
  }

  Future<void> _importCardsFromZip() async {
    if (_isImportingCards) return;

    setState(() => _isImportingCards = true);
    try {
      final zipPath = await ZipService.instance.pickZipFile();
      if (zipPath == null) return;

      final result = await CardImportService.instance.importFromZip(zipPath);
      if (!mounted) return;

      final extra = result.warnings.isEmpty
          ? ''
          : '，${result.warnings.take(2).join('；')}';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${result.message}$extra')));
    } on ZipException catch (error) {
      if (!mounted || error.type == ZipErrorType.canceled) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导入失败：$error')));
    } finally {
      if (mounted) setState(() => _isImportingCards = false);
    }
  }

  Future<void> _showCardCount() async {
    final count = await CardDatabaseHelper.instance.getCardCount();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('本地已保存 $count 张卡片')));
  }

  Future<void> _clearCards() async {
    await CardDatabaseHelper.instance.deleteAllCards();
    await CardImportService.instance.clearImportedAssets();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已清空全部卡片')));
  }

  // ====== UI ======
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
          children: [
            _buildHeader(),
            const SizedBox(height: 24),
            _buildNfcGroup(),
            const SizedBox(height: 24),
            _buildDataGroup(),
            const SizedBox(height: 24),
            _buildAboutGroup(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '设置',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        SizedBox(height: 8),
      ],
    );
  }

  // ---- NFC 分组（进入设置页自动尝试启用 HCE） ----
  Widget _buildNfcGroup() {
    return SettingGroup(
      title: 'NFC 功能状态',
      children: [
        StatusTile(
          icon: Icons.nfc,
          title: '功能状态',
          subtitle: _nfcStatusText,
          trailing: _isLoadingNfc
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(_nfcStatusIcon, color: _nfcStatusColor),
        ),
        StatusTile(
          icon: Icons.smartphone,
          title: 'NFC 硬件',
          subtitle: _nfcHardwareAvailable ? '可用' : '不可用',
          trailing: Icon(
            _nfcHardwareAvailable ? Icons.check : Icons.close,
            color: _nfcHardwareAvailable
                ? const Color(0xFF00966A)
                : Colors.redAccent,
          ),
        ),
        StatusTile(
          icon: Icons.contactless,
          title: 'HCE 支持',
          subtitle: _hceSupported ? '支持' : '不支持',
          trailing: Icon(
            _hceSupported ? Icons.check : Icons.close,
            color: _hceSupported ? const Color(0xFF00966A) : Colors.redAccent,
          ),
        ),
        StatusTile(
          icon: Icons.touch_app,
          title: '卡模拟当前状态',
          subtitle: _isEmulating ? '已启用' : '未启用',
          trailing: Icon(
            _isEmulating ? Icons.play_circle : Icons.pause_circle,
            color: _isEmulating ? const Color(0xFF00966A) : Colors.grey,
          ),
        ),
        StatusTile(
          icon: Icons.account_balance_wallet,
          title: '默认付款应用',
          subtitle: _isDefaultService ? '已设为系统默认触碰付款应用' : '尚未设为默认付款应用',
          trailing: Icon(
            _isDefaultService ? Icons.check_circle : Icons.error_outline,
            color: _isDefaultService ? const Color(0xFF00966A) : Colors.orange,
          ),
        ),
        if (!_isDefaultService)
          ActionTile(
            icon: Icons.verified_user,
            title: '设为默认付款应用',
            subtitle: '唤起系统授权弹窗以接收 payment 分类 AID',
            onTap: _requestDefaultPaymentApp,
          ),
        ActionTile(
          icon: Icons.restart_alt,
          title: '重新检测并启动卡模拟',
          subtitle: '手动重试 HCE 初始化与启用',
          onTap: _restartEmulation,
        ),
        ActionTile(
          icon: _showNfcDebugInfo
              ? Icons.bug_report
              : Icons.bug_report_outlined,
          title: _showNfcDebugInfo ? '隐藏调试信息' : '显示调试信息',
          subtitle: '查看最近 APDU 与 HCE 响应记录',
          onTap: () async {
            setState(() => _showNfcDebugInfo = !_showNfcDebugInfo);
            if (_showNfcDebugInfo) await _refreshNfcDebugInfo();
          },
        ),
        if (_showNfcDebugInfo) ..._buildNfcDebugTiles(),
        ActionTile(
          icon: Icons.settings,
          title: '打开系统 NFC 设置',
          subtitle: '前往系统设置开启 NFC 或配置默认付款应用',
          onTap: () async {
            try {
              await NfcService.instance.openNfcSettings();
            } catch (_) {
              if (mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('无法打开系统设置')));
              }
            }
          },
        ),
      ],
    );
  }

  // ---- 数据管理 ----
  Widget _buildDataGroup() {
    return SettingGroup(
      title: '数据管理',
      children: [
        ActionTile(
          icon: Icons.file_upload,
          title: _isImportingCards ? '正在导入...' : '导入卡片压缩包',
          subtitle: '选择包含 config.json 与 resources 图片的 ZIP 文件',
          onTap: _isImportingCards ? null : _importCardsFromZip,
        ),
        ActionTile(
          icon: Icons.inventory_2,
          title: '查看卡片数量',
          subtitle: '查看本地数据库中保存的卡片数',
          onTap: _showCardCount,
        ),
        ActionTile(
          icon: Icons.delete_sweep,
          title: '清空全部卡片',
          subtitle: '删除本地数据库中所有卡片，操作不可撤销',
          onTap: () =>
              _showConfirmDialog('确认清空全部卡片？', '将删除本地数据库中的所有卡片数据。', _clearCards),
        ),
      ],
    );
  }

  // ---- 关于 ----
  Widget _buildAboutGroup() {
    return SettingGroup(
      title: '关于',
      children: const [
        InfoTile(icon: Icons.info, title: '应用名称', subtitle: '数字钱包'),
        InfoTile(
          icon: Icons.tag,
          title: '发送方式',
          subtitle: 'NFC（自动启用 HCE）',
        ),
        InfoTile(icon: Icons.description, title: '版本', subtitle: '1.0.0'),
      ],
    );
  }

  Future<void> _showConfirmDialog(
    String title,
    String message,
    Future<void> Function() onConfirm,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed == true) await onConfirm();
  }
}
