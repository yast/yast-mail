# encoding: utf-8

# File:
#   clients/mail-server-ldap-setup.ycp
#
# Package:
#   Configuration of mail
#
# Summary:
#   Setup of a LDAP server to be able store the mail server datas
#
# Authors:
#   Peter Varkoly <varkoly@novell.com>
#
# $Id: mail.ycp 37642 2007-04-20 19:06:52Z varkoly $
#
#
module Yast
  class MailServerLdapSetupClient < Client
    def main
      textdomain "mail"
      Yast.import "Label"
      Yast.import "MailServerLDAP"
      Yast.import "Package"
      Yast.import "Report"

      @ERROR = ""
      @args = WFM.Args
      @to_install = ""
      @l_to_install = []


      Builtins.y2milestone("--- mail-server-ldap-setup ---")
      # First we check if all requested modules are installed
      if Builtins.contains(@args, "setup") &&
          !Package.Installed("yast2-ldap-server")
        @l_to_install = Builtins.add(@l_to_install, "yast2-ldap-server")
        @to_install = Ops.add(@to_install, "yast2-ldap-server\n")
      end
      if Builtins.contains(@args, "setup") && !Package.Installed("openldap2")
        @l_to_install = Builtins.add(@l_to_install, "openldap2")
        @to_install = Ops.add(@to_install, "openldap2\n")
      end
      if Builtins.contains(@args, "setup") && !Package.Installed("bind-utils")
        @l_to_install = Builtins.add(@l_to_install, "bind-utils")
        @to_install = Ops.add(@to_install, "bind-utils\n")
      end
      if Builtins.contains(@args, "ca_mgm")
        if !Package.Installed("yast2-ca-management")
          @l_to_install = Builtins.add(@l_to_install, "yast2-ca-management")
          @to_install = Ops.add(@to_install, "yast2-ca-management\n")
        end
      end
      if @to_install != ""
        if Report.AnyQuestion(
            "",
            Ops.add(
              Ops.add(
                _("You have not installed all needed packages.") + "\n",
                @to_install
              ),
              "\n"
            ),
            Label.InstallButton,
            Label.AbortButton,
            :focus_yes
          )
          Package.DoInstall(@l_to_install)
        else
          return false
        end
      end

      #Now we start the requested modules
      WFM.CallFunction("ca_mgm", []) if Builtins.contains(@args, "ca_mgm")
      WFM.CallFunction("ldap-server", []) if Builtins.contains(@args, "setup")
      WFM.CallFunction("ldap", []) if Builtins.contains(@args, "conf")
      if Builtins.contains(@args, "local")
        @LDB = MailServerLDAP.ConfigureLDAPServer
        SCR.Write(
          path(".sysconfig.ldap.BASE_CONFIG_DN"),
          Ops.add("ou=ldapconfig,", Ops.get_string(@LDB, "suffix", ""))
        )
        SCR.Write(
          path(".sysconfig.ldap.BIND_DN"),
          Ops.get_string(@LDB, "rootdn", "")
        )
        SCR.Write(path(".sysconfig.ldap"), nil)
        SCR.Write(
          Builtins.add(path(".etc.ldap_conf.v.\"/etc/ldap.conf\""), "host"),
          ["localhost"]
        )
        SCR.Write(
          Builtins.add(path(".etc.ldap_conf.v.\"/etc/ldap.conf\""), "base"),
          [Ops.get_string(@LDB, "suffix", "")]
        )
        SCR.Write(
          Builtins.add(
            path(".etc.ldap_conf.v.\"/etc/ldap.conf\""),
            "ldap_version"
          ),
          ["3"]
        )
        #SCR::Write (add (.etc.ldap_conf.v."/etc/ldap.conf","ldap_version"), ["3"]);
        #SCR::Write (add (.etc.ldap_conf.v."/etc/ldap.conf","ssl"), ["start_tls"]);
        SCR.Write(path(".etc.ldap_conf"), nil)
      end
      true
    end
  end
end

Yast::MailServerLdapSetupClient.new.main
