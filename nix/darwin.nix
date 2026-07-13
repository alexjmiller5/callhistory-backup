# nix-darwin module: the call history backup as a launchd user agent.
#
# The .app bundle (whose main executable IS callhistory-backup.sh) is built in
# the store and installed to a stable path at activation. TCC keys Full Disk
# Access on code identity, so activation also maintains a stable self-signed
# cert (created once, idempotent) and re-signs the app with it every rebuild —
# ONE manual FDA grant (System Settings → Privacy & Security → Full Disk Access
# → the .app) survives every update. The FDA grant is the only manual step.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.callhistory-backup;
  label = "com.alexmiller.callhistory-backup";
  signingIdentity = "callhistory-backup-signing";
  appInstallPath = "/Applications/CallHistoryBackup.app";

  appBundle = pkgs.runCommand "callhistory-backup-app" { } ''
    mkdir -p "$out/Contents/MacOS"
    cp ${../bundle/Info.plist} "$out/Contents/Info.plist"
    cp ${../callhistory-backup.sh} "$out/Contents/MacOS/callhistory-backup"
    chmod +x "$out/Contents/MacOS/callhistory-backup"
  '';
in
{
  options.services.callhistory-backup = {
    enable = lib.mkEnableOption "the weekly call history backup agent";

    user = lib.mkOption {
      type = lib.types.str;
      description = "Login user the backup runs as (whose CallHistoryDB is read).";
      example = "alexmiller";
    };

    weekday = lib.mkOption {
      type = lib.types.int;
      default = 0;
      description = "Weekday the backup fires (0 = Sunday).";
    };

    hour = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = "Hour (0-23, local time) the backup fires.";
    };

    minute = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = "Minute the backup fires.";
    };
  };

  config = lib.mkIf cfg.enable {
    system.activationScripts.postActivation.text = lib.mkAfter ''
      # Stable self-signed signing cert (one-time, idempotent). A stable cert
      # => stable designated requirement => the FDA grant persists across rebuilds.
      if ! /usr/bin/security find-certificate -c ${signingIdentity} /Library/Keychains/System.keychain >/dev/null 2>&1; then
        echo "creating code-signing identity ${signingIdentity} (one-time)..."
        _t="$(/usr/bin/mktemp -d)"
        /usr/bin/printf '[req]\ndistinguished_name=dn\nx509_extensions=v3\nprompt=no\n[dn]\nCN=%s\n[v3]\nbasicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n' ${signingIdentity} > "$_t/req.cnf"
        /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout "$_t/key.pem" -out "$_t/cert.pem" -config "$_t/req.cnf"
        # non-empty p12 password: `security` rejects empty-password PKCS12
        /usr/bin/openssl pkcs12 -export -inkey "$_t/key.pem" -in "$_t/cert.pem" -out "$_t/id.p12" -passout pass:chb-signing-p12
        /usr/bin/security import "$_t/id.p12" -k /Library/Keychains/System.keychain -P chb-signing-p12 -T /usr/bin/codesign -A
        /bin/rm -rf "$_t"
      fi

      echo "installing ${appInstallPath}..."
      /bin/rm -rf ${appInstallPath}
      /bin/cp -R ${appBundle} ${appInstallPath}
      /bin/chmod -R u+w ${appInstallPath}
      /usr/bin/codesign --force --identifier ${label} --sign ${signingIdentity} ${appInstallPath}
    '';

    launchd.user.agents.callhistory-backup = {
      serviceConfig = {
        Label = label;
        ProgramArguments = [ "${appInstallPath}/Contents/MacOS/callhistory-backup" ];
        # Wall-clock anchored; a slot missed while asleep/off fires once on wake.
        StartCalendarInterval = [ { Weekday = cfg.weekday; Hour = cfg.hour; Minute = cfg.minute; } ];
        RunAtLoad = false;
        StandardOutPath = "/Users/${cfg.user}/Library/Logs/callhistory-backup.log";
        StandardErrorPath = "/Users/${cfg.user}/Library/Logs/callhistory-backup.log";
        ProcessType = "Background";
      };
    };
  };
}
