# Checks the declared units against what the app's setup check verifies:
# enabled, running and bound to the user's configuration.
{
  name = "lg-buddy-module";

  nodes.machine =
    { pkgs, ... }:
    let
      # A paired TV's configuration, as the app writes it.
      configFile = pkgs.writeText "lg-buddy-config.env" ''
        tvs_primary_ip=127.0.0.1
        tvs_primary_mac=02:11:22:33:44:55
        tvs_primary_input=HDMI_1
        tvs_primary_platform=lg_webos
        screen_idle_blank=disabled
        system_sleep_wake_policy=disabled
        updates_auto_check=enabled
      '';
    in
    {
      users.users.alice = {
        isNormalUser = true;
        linger = true;
      };
      services.lg-buddy = {
        enable = true;
        user = "alice";
      };
      systemd.tmpfiles.rules = [
        "d /home/alice/.config 0700 alice users -"
        "d /home/alice/.config/lg-buddy 0700 alice users -"
        "C /home/alice/.config/lg-buddy/config.env 0600 alice users - ${configFile}"
      ];
    };

  testScript = ''
    config = "/home/alice/.config/lg-buddy/config.env"
    user = "systemctl --user -M alice@ "

    machine.wait_for_unit("multi-user.target")
    machine.succeed(f"test -f {config}")
    machine.wait_for_unit("user@1000.service")

    machine.succeed("systemctl is-enabled LG_Buddy.service LG_Buddy_lifecycle.service")
    machine.wait_for_unit("LG_Buddy_lifecycle.service")
    # Still running well after start, not cycling through restarts.
    machine.sleep(15)
    machine.succeed("systemctl is-active LG_Buddy_lifecycle.service")
    assert machine.succeed("systemctl show -p NRestarts --value LG_Buddy_lifecycle.service").strip() == "0"
    for unit in ["LG_Buddy.service", "LG_Buddy_lifecycle.service"]:
        env = machine.succeed(f"systemctl show -p Environment --value {unit}")
        assert f"LG_BUDDY_CONFIG={config}" in env.split(), env
        machine.succeed(f"test -z \"$(systemctl show -p EnvironmentFiles --value {unit})\"")

    machine.succeed(user + "is-enabled LG_Buddy_screen.service LG_Buddy_update_check.timer")
    for unit in ["LG_Buddy_screen.service", "LG_Buddy_update_check.service"]:
        env = machine.succeed(user + f"show -p Environment --value {unit}")
        assert f"LG_BUDDY_CONFIG={config}" in env.split(), env

    assert machine.succeed("cat /usr/lib/lg-buddy/config-path").strip() == config
    machine.succeed("test -x /etc/NetworkManager/dispatcher.d/pre-down.d/LG_Buddy_lifecycle")
    machine.succeed("test -d /run/lg_buddy")
  '';
}
