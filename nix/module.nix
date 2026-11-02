# NixOS module declaring LG Buddy's system and user services.
#
# On NixOS the setup flow does not install services itself; it verifies that
# the loaded units are enabled, running and bound to the user's configuration
# through LG_BUDDY_CONFIG. This module declares the same units, hooks and
# configuration pointer the shell installer writes on other distributions.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.lg-buddy;
  exe = lib.getExe cfg.package;
  environment.LG_BUDDY_CONFIG = cfg.configFile;
  configPointer = pkgs.writeText "lg-buddy-config-path" "${cfg.configFile}\n";
  # System lifecycle handling waits for the network with nm-online and reads
  # NetworkManager's journal with journalctl, both looked up on PATH.
  lifecyclePath = [
    config.systemd.package
  ]
  ++ lib.optional config.networking.networkmanager.enable config.networking.networkmanager.package;
in
{
  options.services.lg-buddy = {
    enable = lib.mkEnableOption "LG Buddy, which controls an LG webOS TV used as a PC display";

    package = lib.mkOption {
      type = lib.types.package;
      description = "The LG Buddy package to use.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      example = "alice";
      description = ''
        The user who pairs the TV in the LG Buddy app. LG Buddy manages one TV,
        and every service reads this user's configuration.
      '';
    };

    configFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.users.users.${cfg.user}.home}/.config/lg-buddy/config.env";
      defaultText = lib.literalExpression ''"''${config.users.users.''${config.services.lg-buddy.user}.home}/.config/lg-buddy/config.env"'';
      description = ''
        Path to the configuration the app writes when the TV is paired. The
        app's setup check requires every service to use this path.
      '';
    };

    updateCheck.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to enable the weekly background update check timer. This must
        match the app's automatic update checks setting (`updates.auto_check`),
        which is on by default; if you turn that setting off, set this to false
        as well.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # Resolved by commands started outside the services, such as the
    # NetworkManager hook and the app itself.
    systemd.tmpfiles.rules = [
      "d /run/lg_buddy 0755 root root -"
      "d /usr/lib/lg-buddy 0755 root root -"
      "L+ /usr/lib/lg-buddy/config-path - - - - ${configPointer}"
    ];

    environment.etc."NetworkManager/dispatcher.d/pre-down.d/LG_Buddy_lifecycle" = {
      mode = "0755";
      text = ''
        #!/bin/sh
        set -eu
        [ "''${2:-}" = pre-down ] || exit 0
        PATH=${lib.makeBinPath lifecyclePath}''${PATH:+:$PATH}
        export PATH
        exec ${exe} nm-pre-down
      '';
    };

    systemd.services.LG_Buddy = {
      description = "Controls LG WebOS TV at Startup and Shutdown";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      startLimitIntervalSec = 30;
      startLimitBurst = 5;
      path = lifecyclePath;
      inherit environment;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${exe} startup boot";
        ExecStop = "${exe} shutdown";
      };
    };

    systemd.services.LG_Buddy_lifecycle = {
      description = "LG Buddy system sleep/wake lifecycle monitor";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      path = lifecyclePath;
      inherit environment;
      serviceConfig = {
        Type = "simple";
        ExecStart = "${exe} lifecycle";
        Restart = "on-failure";
        RestartSec = 10;
      };
    };

    systemd.user.services.LG_Buddy_screen = {
      description = "LG Buddy Screen Monitor Service";
      after = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      unitConfig.ConditionUser = cfg.user;
      inherit environment;
      serviceConfig = {
        ExecStart = "${exe} monitor";
        Restart = "always";
        RestartSec = 10;
      };
    };

    systemd.user.services.LG_Buddy_update_check = {
      description = "LG Buddy background update check";
      after = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      unitConfig.ConditionUser = cfg.user;
      inherit environment;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${exe} updates background-check";
      };
    };

    systemd.user.timers.LG_Buddy_update_check = lib.mkIf cfg.updateCheck.enable {
      description = "LG Buddy background update check timer";
      after = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      unitConfig.ConditionUser = cfg.user;
      timerConfig = {
        OnCalendar = "weekly";
        RandomizedDelaySec = "12h";
        Persistent = true;
      };
    };
  };
}
