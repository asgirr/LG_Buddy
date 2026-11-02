# Checks the declared units against what the app's setup check verifies:
# enabled, running and bound to the user's configuration.
{
  name = "lg-buddy-module";

  nodes.machine = {
    users.users.alice = {
      isNormalUser = true;
      linger = true;
    };
    services.lg-buddy = {
      enable = true;
      user = "alice";
    };
  };

  testScript = ''
    config = "/home/alice/.config/lg-buddy/config.env"
    user = "systemctl --user -M alice@ "

    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("user@1000.service")

    machine.succeed("systemctl is-enabled LG_Buddy.service LG_Buddy_lifecycle.service")
    machine.wait_for_unit("LG_Buddy_lifecycle.service")
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
