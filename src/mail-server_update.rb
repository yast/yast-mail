# encoding: utf-8

module Yast
  class MailServerUpdateClient < Client
    def main
      textdomain "openschool-server"
      Yast.import "YaPI::MailServer"
      Yast.import "Ldap"
      @out = Convert.to_map(
        SCR.Execute(path(".target.bash_output"), "/usr/sbin/oss_get_admin_pw")
      )
      @ldappasswd = Builtins.tostring(Ops.get_string(@out, "stdout", ""))
      @ldappasswd = Ldap.GetLDAPPassword(false) if @ldappasswd == ""
      YaPI::MailServer.UpdateMailServerTables(@ldappasswd)

      nil
    end
  end
end

Yast::MailServerUpdateClient.new.main
