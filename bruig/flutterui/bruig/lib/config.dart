import 'dart:io';
import 'package:args/args.dart';
import "package:ini/ini.dart" as ini;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

const APPNAME = "bruig";

String homeDir() {
  var env = Platform.environment;
  if (Platform.isWindows) {
    return env['UserProfile'] ?? "";
  } else {
    return env['HOME'] ?? "";
  }
}

String cleanAndExpandPath(String p) {
  if (p == "") {
    return p;
  }

  if (p.startsWith("~")) {
    p = homeDir() + p.substring(1);
  }

  return path.canonicalize(p);
}

Future<String> defaultAppDataDir() async {
  if (Platform.isLinux) {
    final home = Platform.environment["HOME"];
    if (home != null && home != "") {
      return path.join(home, ".$APPNAME");
    }
  }

  if (Platform.isWindows && Platform.environment.containsKey("LOCALAPPDATA")) {
    return path.join(Platform.environment["LOCALAPPDATA"]!, APPNAME);
  }

  if (Platform.isMacOS) {
    // getApplicationSupportDirectory adds "com.foo.bar" to application support,
    // so go to parent and append default APPNAME.
    final baseDir = (await getApplicationSupportDirectory()).parent.path;
    return path.join(baseDir, APPNAME);
  }

  // Default behavior: use app support dir.
  final dir = await getApplicationSupportDirectory();
  return dir.path;
}

String defaultLndDir() {
  return path.join(homeDir(), ".dcrlnd");
}

class Config {
  late final String appDataDir;
  late final String dbRoot;
  late final String downloadsDir;
  late final String serverAddr;
  late final String lnRPCHost;
  late final String lnTLSCert;
  late final String lnMacaroonPath;
  late final String logFile;
  late final String msgRoot;
  late final String debugLevel;
  late final String walletType;
  late final String network;
  late final String internalWalletDir;
  late final String resourcesUpstream;
  late final String simpleStorePayType;
  late final String simpleStoreAccount;
  late final double simpleStoreShipCharge;
  late final String proxyaddr;
  late final bool torIsolation;
  late final String proxyUsername;
  late final String proxyPassword;
  late final int circuitLimit;
  late final bool noLoadChatHistory;
  late final bool syncFreeList;

  Config();
  Config.filled(
      {this.appDataDir: "",
      this.dbRoot: "",
      this.downloadsDir: "",
      this.serverAddr: "",
      this.lnRPCHost: "",
      this.lnTLSCert: "",
      this.lnMacaroonPath: "",
      this.logFile: "",
      this.msgRoot: "",
      this.debugLevel: "",
      this.walletType: "",
      this.network: "",
      this.internalWalletDir: "",
      this.resourcesUpstream: "",
      this.simpleStorePayType: "",
      this.simpleStoreAccount: "",
      this.simpleStoreShipCharge: 0,
      this.proxyaddr: "",
      this.torIsolation: false,
      this.proxyUsername: "",
      this.proxyPassword: "",
      this.circuitLimit: 32,
      this.noLoadChatHistory: true,
      this.syncFreeList: true});
  factory Config.newWithRPCHost(
          Config cfg, String rpcHost, String tlsCert, String macaroonPath) =>
      Config.filled(
        appDataDir: cfg.appDataDir,
        dbRoot: cfg.dbRoot,
        downloadsDir: cfg.downloadsDir,
        serverAddr: cfg.serverAddr,
        lnRPCHost: rpcHost,
        lnTLSCert: tlsCert,
        lnMacaroonPath: macaroonPath,
        logFile: cfg.logFile,
        msgRoot: cfg.msgRoot,
        debugLevel: cfg.debugLevel,
        walletType: cfg.walletType,
        network: cfg.network,
        internalWalletDir: cfg.internalWalletDir,
        resourcesUpstream: cfg.resourcesUpstream,
        simpleStorePayType: cfg.simpleStorePayType,
        simpleStoreAccount: cfg.simpleStoreAccount,
        simpleStoreShipCharge: cfg.simpleStoreShipCharge,
        proxyaddr: cfg.proxyaddr,
        torIsolation: cfg.torIsolation,
        proxyUsername: cfg.proxyUsername,
        proxyPassword: cfg.proxyPassword,
        circuitLimit: cfg.circuitLimit,
        noLoadChatHistory: cfg.noLoadChatHistory,
        syncFreeList: cfg.syncFreeList,
      );

  Future<void> saveConfig(String filepath) async {
    var f = ini.Config.fromString("\n[payment]\n");
    var set = (String section, String opt, String val) =>
        val != "" ? f.set(section, opt, val) : null;

    // Do not save the root app data path in ios, but rely on defaultAppDataDir()
    // to return the correct path on every execution, because the root path changes
    // on every recompilation.
    if (!Platform.isIOS) {
      set("default", "root", appDataDir);
    }
    set("default", "server", serverAddr);
    set("payment", "wallettype", walletType);
    set("payment", "network", network);
    if (walletType == "external") {
      set("payment", "lnrpchost", lnRPCHost);
      set("payment", "lntlscert", lnTLSCert);
      set("payment", "lnmacaroonpath", lnMacaroonPath);
    }

    // Create the dir and write the config file.
    await File(filepath).parent.create(recursive: true);
    await File(filepath).writeAsString(f.toString());
  }
}

Future<Config> loadConfig(String filepath) async {
  var f = ini.Config.fromStrings(File(filepath).readAsLinesSync());
  var appDataDir = await defaultAppDataDir();
  var iniAppData = f.get("default", "root");
  if (iniAppData != null && iniAppData != "") {
    appDataDir = cleanAndExpandPath(iniAppData);
  }

  String getPath(String section, String option, String def) {
    var iniVal = f.get(section, option);
    if (iniVal == null || iniVal == "") {
      return def;
    }
    return cleanAndExpandPath(iniVal);
  }

  var getBool = (String section, String opt) {
    var v = f.get(section, opt);
    return v == "yes" || v == "true" || v == "1" ? true : false;
  };

  var getBoolDefaultTrue = (String section, String opt) {
    var v = f.get(section, opt);
    return v == "no" || v == "false" || v == "0" ? false : true;
  };

  var getInt = (String section, String opt) {
    var v = f.get(section, opt);
    return v != null && v != "" ? int.tryParse(v) : null;
  };

  var iniLogFile = f.get("log", "logfile");
  String logfile = path.join(appDataDir, "applogs", "${APPNAME}.log");
  if (iniLogFile != null) {
    iniLogFile = iniLogFile.trim();

    if (iniLogFile == "") {
      logfile = "";
    } else if (!iniLogFile.contains("/") && !iniLogFile.contains("\\")) {
      // logfile does not contain path separator. Use default dir with the
      // specified file name.
      logfile = path.join(appDataDir, "logs", iniLogFile);
    } else {
      logfile = cleanAndExpandPath(iniLogFile);
    }
  }

  String msgRoot = path.join(appDataDir, "logs");
  var iniMsgsRoot = f.get("log", "msglog");
  if (iniMsgsRoot != null) {
    iniMsgsRoot = iniMsgsRoot.trim();
    if (iniMsgsRoot == "") {
      msgRoot = "";
    } else if (!iniMsgsRoot.contains("/") && !iniMsgsRoot.contains("\\")) {
      // msgsroot does not contain path separator. Use default dir with the
      // specified subdir name.
      msgRoot = path.join(appDataDir, iniMsgsRoot);
    } else {
      msgRoot = cleanAndExpandPath(iniMsgsRoot);
    }
  }

  var c = Config();
  c.appDataDir = appDataDir;
  c.dbRoot = path.join(appDataDir, "db");
  c.downloadsDir = path.join(appDataDir, "downloads");
  c.serverAddr = f.get("default", "server") ?? "localhost:12345";
  c.logFile = logfile;
  c.msgRoot = msgRoot;
  c.debugLevel = f.get("log", "debuglevel") ?? "info";
  c.walletType = f.get("payment", "wallettype") ?? "disabled";
  c.network = f.get("payment", "network") ?? "mainnet";
  c.internalWalletDir = path.join(appDataDir, "ln-wallet");

  c.proxyaddr = f.get("default", "proxyaddr") ?? "";
  c.proxyUsername = f.get("default", "proxyuser") ?? "";
  c.proxyPassword = f.get("default", "proxypass") ?? "";
  c.torIsolation = getBool("default", "torisolation");
  c.circuitLimit = getInt("default", "circuitlimit") ?? 32;
  c.noLoadChatHistory = getBool("default", "noloadchathistory");
  c.syncFreeList = getBoolDefaultTrue("default", "syncfreelist");

  if (c.walletType != "disabled") {
    c.lnRPCHost = f.get("payment", "lnrpchost") ?? "localhost:10009";
    c.lnTLSCert =
        getPath("payment", "lntlscert", path.join(defaultLndDir(), "tls.cert"));
    c.lnMacaroonPath = getPath(
        "payment",
        "lnmacaroonpath",
        path.join(defaultLndDir(), "data", "chain", "decred", "mainnet",
            "admin.macaroon"));
  } else {
    c.lnRPCHost = "";
    c.lnTLSCert = "";
    c.lnMacaroonPath = "";
  }

  var resUpstream = f.get("resources", "resourcesupstream") ?? "";
  if (resUpstream.startsWith("pages:")) {
    var path = resUpstream.substring("pages:".length);
    path = cleanAndExpandPath(path);
    resUpstream = "pages:$path";
  } else if (resUpstream.startsWith("simplestore:")) {
    var path = resUpstream.substring("simplestore:".length);
    path = cleanAndExpandPath(path);
    resUpstream = "simplestore:$path";
  }

  c.resourcesUpstream = resUpstream;
  c.simpleStorePayType = f.get("resources", "simplestorepaytype") ?? "";
  c.simpleStoreAccount = f.get("resources", "simplestoreaccount") ?? "";
  c.simpleStoreShipCharge =
      double.tryParse(f.get("resources", "simplestoreshipcharge") ?? "0") ?? 0;

  return c;
}

final usageException = Exception("Usage Displayed");
final newConfigNeededException = Exception("Config needed");
final unableToMoveOldWallet = Exception("Existing wallet in new location");

Future<String> configFileName(List<String> args) async {
  var defaultCfgFile = path.join(await defaultAppDataDir(), "${APPNAME}.conf");
  var p = ArgParser();
  p.addOption("configfile", abbr: "c", defaultsTo: defaultCfgFile);
  var res = p.parse(args);
  return res["configfile"];
}

Future<Config> configFromArgs(List<String> args) async {
  var p = ArgParser();
  var defaultCfgFile = path.join(await defaultAppDataDir(), "${APPNAME}.conf");
  p.addFlag("help", abbr: "h", help: "Display usage info", negatable: false);
  p.addOption("configfile",
      abbr: "c", defaultsTo: defaultCfgFile, help: "Path to config file");
  var res = p.parse(args);

  if (res["help"]) {
    print(p.usage);
    throw usageException;
  }

  var cfgFilePath = res["configfile"];
  if (!File(cfgFilePath).existsSync()) {
    throw newConfigNeededException;
  }

  return loadConfig(cfgFilePath);
}
