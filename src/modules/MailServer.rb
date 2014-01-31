# encoding: utf-8

# File:	modules/MailServer.ycp
# Package:	Configuration of mail-server
# Summary:	MailServer settings, input and output functions
# Authors:	Peter Varkoly <varkoly@suse.de>
#
# $Id: MailServer.ycp 30905 2006-05-12 17:27:32Z varkoly $
#
# Representation of the configuration of mail-server.
# Input and output routines.
require "yast"

module Yast
  class MailServerClass < Module
    def main
      textdomain "mail"

      Yast.import "Ldap"
      Yast.import "Label"
      Yast.import "Package"
      Yast.import "Popup"
      Yast.import "Progress"
      Yast.import "Report"
      Yast.import "Summary"
      Yast.import "YaPI::MailServer"
      Yast.import "NetworkInterfaces"
      Yast.import "Service"
      Yast.import "Users"

      # Data was modified?
      @modified = false


      @proposal_valid = false

      # Abort function
      # return boolean return true if abort
      @AbortFunction = fun_ref(method(:Modified), "boolean ()")

      # Settings: Define all variables needed for configuration of mail-server
      # True if the modul was started with the option 'setup'.
      @setup = false

      # True if there is server certificate.
      @CertExist = false

      # Map of the mail server global settings.
      @GlobalSettings = {}

      # Map of the mail transport settings.
      @MailTransports = {}

      # Map of the mail server prevention settings.
      @MailPrevention = {}

      # Map of the mail server relaying settings.
      @MailRelaying = {}

      # Map of the mail server local delivery settings.
      @MailLocalDelivery = {}

      # Map of the mail server fetching mail jobs.
      @FetchingMail = {}

      # Map of the mail server local domains.
      @MailLocalDomains = {}

      # Map of the mail server local domains.
      @LDAPDefaults = {}

      # List of the PPP devices
      @PPPCards = []

      # Some additional parameter needed for the configuration.
      @AdminPassword = nil

      # List of the Configuration Modules
      @ModulesTreeContent = [
        [_("Global Settings"), "GlobalSettings"],
        [_("Local Delivery"), "MailLocalDelivery"],
        [_("Mail Transports"), "MailTransports"],
        [_("Mailserver Prevention"), "MailPrevention"],
        [_("Mailserver Relaying"), "MailRelaying"],
        [_("Fetching Mail"), "FetchingMail"],
        [_("Mailserver Domains"), "MailLocalDomains"]
      ]

      @pam_ldap_installed = false
      @nss_ldap_installed = false
      @procmail_installed = false
      @ldap_installed = false
      @imap_installed = false
      @postfix_installed = false
      @fetchmail_installed = false
      @sasl_installed = false
      @saslauthd_installed = false
      @plugins_installed = false
      @amavis_installed = false
      @spamassassin_installed = false
      @clamav_installed = false
    end

    # Abort function
    # @return blah blah lahjk
    def Abort
      #    if(AbortFunction != nil)
      #	return eval(AbortFunction) == true;
      false
    end

    # Data was modified?
    # @return true if modified
    def Modified
      if Ops.get_boolean(@GlobalSettings, "Changed", false) ||
          Ops.get_boolean(@MailTransports, "Changed", false) ||
          Ops.get_boolean(@MailPrevention, "Changed", false) ||
          Ops.get_boolean(@MailRelaying, "Changed", false) ||
          Ops.get_boolean(@MailLocalDelivery, "Changed", false) ||
          Ops.get_boolean(@FetchingMail, "Changed", false) ||
          Ops.get_boolean(@MailLocalDomains, "Changed", false)
        @modified = true
      end
      Builtins.y2debug("modified=%1", @modified)
      @modified
    end
    # Is a package installed?
    # @param [String] package package name, without version or .rpm suffix
    # @return true/false
    def Installed(package)
      Package.Installed(package)
    end

    # Help funktion to check the DNS Settings

    def Check_Mail_Domain
      _LDAPSettings = Ldap.Export
      _DNSWarning = _("There is no main mail domain defined. Please fix it!")

      # looking if a mail domain exist
      searchmap = {
        "base_dn"      => Ops.get_string(_LDAPSettings, "base_config_dn", ""),
        "filter"       => "objectClass=suseDnsConfiguration",
        "attrs"        => ["suseDefaultBase"],
        "not_found_ok" => false,
        "scope"        => 2
      }
      modulesDns = Convert.to_list(SCR.Read(path(".ldap.search"), searchmap))
      dns_base = Ops.get_string(modulesDns, [0, "suseDefaultBase", 0], "")

      searchmap = {
        "base_dn"      => dns_base,
        "filter"       => "(&(objectClass=dNSZone)(relativeDomainName=@))",
        "not_found_ok" => false,
        "map"          => true,
        "scope"        => 2
      }
      counter = 0
      domains = Convert.convert(
        SCR.Read(path(".ldap.search"), searchmap),
        :from => "any",
        :to   => "map <string, map>"
      )

      if domains == nil || domains == {}
        Popup.Warning(_DNSWarning)
        return
      end
      is_main_domain = false
      Builtins.foreach(domains) do |dn, domain|
        if Ops.get_string(domain, ["suseMailDomainType", 0], "") == "main"
          is_main_domain = true
          raise Break
        end
      end
      if !is_main_domain
        Builtins.y2milestone("no main mail domain")
        Ops.set(_LDAPSettings, "bind_pw", @AdminPassword)
        SCR.Execute(path(".ldap.bind"), _LDAPSettings)
        counter2 = 0
        lastDomain = {}
        lastDn = ""
        # evaluate if there is ONE domain with not containing
        # ".in-addr.arpa" inf the zone Name
        Builtins.foreach(domains) do |dn, domain|
          if Ops.less_than(
              Builtins.size(
                Ops.get_string(Ops.get_list(domain, "zonename", []), 0, "")
              ),
              Builtins.size(".in-addr.arpa")
            ) ||
              Builtins.substring(
                Ops.get_string(Ops.get_list(domain, "zonename", []), 0, ""),
                Ops.subtract(
                  Builtins.size(
                    Ops.get_string(Ops.get_list(domain, "zonename", []), 0, "")
                  ),
                  Builtins.size(".in-addr.arpa")
                )
              ) != ".in-addr.arpa"
            Ops.set(
              domain,
              "objectClass",
              Builtins.add(
                Ops.get_list(domain, "objectClass", []),
                "suseMailDomain"
              )
            )
            Ops.set(domain, "suseMailDomainType", ["main"])
            Ops.set(domain, "suseMailDomainMasquerading", ["yes"])
            lastDomain = deep_copy(domain)
            lastDn = dn
            counter2 = Ops.add(counter2, 1)
          end
        end
        if counter2 == 1
          # set the ONE to main domain
          Builtins.y2milestone(
            "Setting main mail domain: %1; %2",
            lastDn,
            lastDomain
          )
          SCR.Write(path(".ldap.modify"), { "dn" => lastDn }, lastDomain)
        else
          # user has to decide
          Report.Error(_DNSWarning)
        end
      end
      nil
    end

    # Check if all needed packages are installed
    # @return true on success
    def CheckPackages
      @pam_ldap_installed = Installed("pam_ldap")
      @nss_ldap_installed = Installed("nss_ldap")
      @procmail_installed = Installed("procmail")
      @imap_installed = Installed("dovecot")
      @postfix_installed = Installed("postfix")
      @fetchmail_installed = Installed("fetchmail")
      @ldap_installed = Installed("yast2-ldap-client")
      @sasl_installed = Installed("cyrus-sasl-plain")
      @saslauthd_installed = Installed("cyrus-sasl-saslauthd")
      @plugins_installed = Installed("yast2-mail-plugins")
      @amavis_installed = Installed("amavisd-new")
      @clamav_installed = Installed("clamav")
      @spamassassin_installed = Installed("spamassassin")
      to_install = ""
      l_to_install = []

      if !@pam_ldap_installed
        l_to_install = Builtins.add(l_to_install, "pam_ldap")
        to_install = Ops.add(to_install, "pam_ldap\n")
      end
      if !@nss_ldap_installed
        l_to_install = Builtins.add(l_to_install, "nss_ldap")
        to_install = Ops.add(to_install, "nss_ldap\n")
      end
      if !@postfix_installed
        l_to_install = Builtins.add(l_to_install, "postfix")
        to_install = Ops.add(to_install, "postfix\n")
      end
      if !@ldap_installed
        l_to_install = Builtins.add(l_to_install, "yast2-ldap-client")
        to_install = Ops.add(to_install, "yast2-ldap-client\n")
      end
      if !@sasl_installed
        l_to_install = Builtins.add(l_to_install, "cyrus-sasl-plain")
        to_install = Ops.add(to_install, "cyrus-sasl-plain\n")
      end
      if !@saslauthd_installed
        l_to_install = Builtins.add(l_to_install, "cyrus-sasl-saslauthd")
        to_install = Ops.add(to_install, "cyrus-sasl-saslauthd\n")
      end
      if !@plugins_installed
        l_to_install = Builtins.add(l_to_install, "yast2-mail-plugins")
        to_install = Ops.add(to_install, "yast2-mail-plugins\n")
      end
      if to_install != ""
        if Report.AnyQuestion(
            "",
            Ops.add(
              Ops.add(
                _("You have not installed all needed packages.") + "\n",
                to_install
              ),
              "\n"
            ),
            Label.InstallButton,
            Label.AbortButton,
            :focus_yes
          )
          Package.DoInstall(l_to_install)
        else
          return false
        end
      end
      true
    end

    # Read all mail-server settings
    # @return true on success
    def Read
      # MailServer read dialog caption
      caption = _("Reading the Mail Server Settings")

      steps = 8

      sl = 10

      Builtins.y2milestone("----- Start MailServer::Read -----")

      # We do not set help text here, because it was set outside
      Progress.New(
        caption,
        "",
        steps,
        [
          # Progress stage 0/7
          _("Read needed packages"),
          # Progress stage 1/7
          _("Read mail server global settings"),
          # Progress stage 2/7
          _("Read mail server transports"),
          # Progress stage 3/7
          _("Read mail server prevention settings"),
          # Progress stage 4/7
          _("Read mail server relaying settings"),
          # Progress stage 5/7
          _("Read mail server local delivery settings"),
          # Progress stage 6/7
          _("Read mail fetching jobs"),
          # Progress stage 7/7
          _("Read mail server domains")
        ],
        [
          # Progress stage 0/7
          _("Reading packages..."),
          # Progress stage 1/7
          _("Reading mail server global settings..."),
          # Progress stage 2/7
          _("Reading mail server transports..."),
          # Progress stage 3/7
          _("Reading mail server prevention settings..."),
          # Progress stage 4/7
          _("Reading mail server relaying settings..."),
          # Progress stage 5/7
          _("Reading mail server local delivery settings..."),
          # Progress stage 6/3
          _("Reading mail fetching jobs..."),
          # Progress stage 7/7
          _("Reading mail server domains..."),
          # Progress finished
          _("Finished")
        ],
        ""
      )

      # read  packages
      return false if Abort()
      Progress.NextStage
      return false if !CheckPackages()
      Builtins.sleep(sl)

      NetworkInterfaces.Read
      _TMP = NetworkInterfaces.Export("modem")
      Builtins.foreach(
        Convert.convert(
          Ops.get(_TMP, "ppp", {}),
          :from => "map",
          :to   => "map <string, map>"
        )
      ) { |k, v| @PPPCards = Builtins.add(@PPPCards, Ops.add("ppp", k)) }
      _TMP = NetworkInterfaces.Export("isdn")
      Builtins.foreach(
        Convert.convert(
          Ops.get(_TMP, "ipp", {}),
          :from => "map",
          :to   => "map <string, map>"
        )
      ) { |k, v| @PPPCards = Builtins.add(@PPPCards, Ops.add("ipp", k)) }
      _TMP = NetworkInterfaces.Export("dsl")
      Builtins.foreach(
        Convert.convert(
          Ops.get(_TMP, "dsl", {}),
          :from => "map",
          :to   => "map <string, map>"
        )
      ) { |k, v| @PPPCards = Builtins.add(@PPPCards, Ops.add("dsl", k)) }


      # read  global settings
      return false if Abort()
      Progress.NextStage
      @GlobalSettings = YaPI::MailServer.ReadGlobalSettings(@AdminPassword)
      # Error message
      if @GlobalSettings == nil
        Report.Error(_("Cannot read the mail server global settings."))
      end
      Builtins.sleep(sl)

      # read mail transports
      return false if Abort()
      Progress.NextStep
      @MailTransports = YaPI::MailServer.ReadMailTransports(@AdminPassword)
      # Error message
      if @MailTransports == nil
        Report.Error(_("Cannot read mail server transports."))
      end
      Builtins.sleep(sl)

      # read mail preventions
      return false if Abort()
      Progress.NextStage
      @MailPrevention = Convert.convert(
        YaPI::MailServer.ReadMailPrevention(@AdminPassword),
        :from => "any",
        :to   => "map <string, any>"
      )
      # Error message
      if @MailPrevention == nil
        Report.Error(_("Cannot read mail server preventions."))
      end
      Builtins.sleep(sl)

      # read mail realaying
      return false if Abort()
      Progress.NextStage
      @MailRelaying = Convert.convert(
        YaPI::MailServer.ReadMailRelaying(@AdminPassword),
        :from => "any",
        :to   => "map <string, any>"
      )
      # Error message
      if @MailRelaying == nil
        Report.Warning(_("Cannot read the mail server relay settings."))
      end
      Builtins.sleep(sl)

      # read mail local delivery
      return false if Abort()
      Progress.NextStage
      @MailLocalDelivery = Convert.convert(
        YaPI::MailServer.ReadMailLocalDelivery(@AdminPassword),
        :from => "any",
        :to   => "map <string, any>"
      )
      # Error message
      if @MailLocalDelivery == nil
        Report.Warning(
          _("Cannot read the mail server local delivery settings.")
        )
      end
      if Ops.get_string(@MailLocalDelivery, "Type", "") != "none"
        Check_Mail_Domain()
      end
      Builtins.sleep(sl)

      # read mail server fetching jobs
      return false if Abort()
      Progress.NextStage
      @FetchingMail = Convert.convert(
        YaPI::MailServer.ReadFetchingMail(@AdminPassword),
        :from => "any",
        :to   => "map <string, any>"
      )
      # Error message
      if @FetchingMail == nil
        Report.Warning(_("Cannot read the mail server fetching jobs."))
      end
      Builtins.sleep(sl)

      # read mail server local domains
      return false if Abort()
      Progress.NextStage
      @MailLocalDomains = Convert.convert(
        YaPI::MailServer.ReadMailLocalDomains(@AdminPassword),
        :from => "any",
        :to   => "map <string, any>"
      )
      # Error message
      if @MailLocalDomains == nil
        Report.Warning(_("Cannot read the mail server domains."))
      end
      Builtins.sleep(sl)

      return false if Abort()
      # Progress finished
      Progress.NextStage
      Builtins.sleep(sl)

      return false if Abort()
      true
    end

    # Write all mail-server settings
    # @return true on success
    def Write
      # MailServer read dialog caption
      caption = _("Saving Mail Server Configuration")

      steps = 8

      sl = 500
      Builtins.sleep(sl)

      # We do not set help text here, because it was set outside
      Progress.New(
        caption,
        " ",
        steps,
        [
          # Progress stage 1/7
          _("Write mail server global settings"),
          # Progress stage 2/7
          _("Write mail server local delivery settings"),
          # Progress stage 3/7
          _("Write mail server transports"),
          # Progress stage 4/7
          _("Write mail server prevention settings"),
          # Progress stage 5/7
          _("Write mail server relaying settings"),
          # Progress stage 6/3
          _("Write mail fetching jobs"),
          # Progress stage 7/7
          _("Write mail server domains")
        ],
        [
          # Progress stage 1/7
          _("Writing mail server global settings..."),
          # Progress stage 2/7
          _("Writing mail server local delivery settings..."),
          # Progress stage 3/7
          _("Writing mail server transports..."),
          # Progress stage 4/7
          _("Writing mail server prevention settings..."),
          # Progress stage 5/7
          _("Writing mail server relaying settings..."),
          # Progress stage 6/3
          _("Writing mail fetching jobs..."),
          # Progress stage 7/7
          _("Writing mail server domains..."),
          # Progress finished
          _("Finished")
        ],
        ""
      )

      # write
      SCR.Write(path(".sysconfig.mail.MAIL_CREATE_CONFIG"), "no")
      SCR.Write(path(".sysconfig.mail"), nil)

      # write  global settings
      return false if Abort()
      Progress.NextStage
      if Ops.get_boolean(@GlobalSettings, "Changed", false)
        if !YaPI::MailServer.WriteGlobalSettings(
            @GlobalSettings,
            @AdminPassword
          )
          Report.Error(_("Cannot write the mail server global settings."))
        end
      end
      Builtins.sleep(sl)

      # write mail local delivery
      # first we looking for if all the needed packages are installed
      if Ops.get_string(@MailLocalDelivery, "Type", "none") == "procmail"
        if !@procmail_installed
          if Report.AnyQuestion(
              "",
              _("You have not installed all needed packages.") + "\n procmail \n",
              Label.InstallButton,
              Label.AbortButton,
              :focus_yes
            )
            Package.DoInstall(["procmail"])
          else
            return false
          end
        end
      end

      if Ops.greater_than(Service.Status("saslauthd"), 0)
        Service.Start("saslauthd")
        Service.Enable("saslauthd")
      end

      if Ops.get_string(@MailLocalDelivery, "Type", "none") == "imap"
        if !@imap_installed
          if Report.AnyQuestion(
              "",
              _("You have not installed all needed packages.") + "\n dovecot \n",
              Label.InstallButton,
              Label.AbortButton,
              :focus_yes
            )
            Package.DoInstall(["dovecot"])
            SCR.UnmountAgent(path(".etc.imapd_conf"))
          else
            return false
          end
        end
#TODO dovecot's admin password!
        crypted = Users.CryptPassword(@AdminPassword, "system", "foo")
        SCR.Write(path(".target.passwd.cyrus"), crypted)
        Builtins.y2milestone("--- Enabling dovecot --")
        Service.Enable("dovecot")
      else
        if @imap_installed
          Service.Stop("dovecot")
          Service.Disable("dovecot")
        end
      end
      return false if Abort()
      Progress.NextStage
      if Ops.get_boolean(@MailLocalDelivery, "Changed", false)
        if !YaPI::MailServer.WriteMailLocalDelivery(
            @MailLocalDelivery,
            @AdminPassword
          )
          Report.Warning(
            _("Cannot write the mail server local delivery settings.")
          )
        end
        if Ops.get_string(@MailLocalDelivery, "Type", "none") == "imap"
          Builtins.y2milestone("--- Stop imap --")
          Service.Stop("dovecot")
          Builtins.y2milestone("--- Start dovecot --")
          Service.Start("dovecot")
          Builtins.sleep(10000)
          YaPI::MailServer.CreateRootMailbox(@AdminPassword)
        end
      end
      Builtins.sleep(sl)

      # write mail transports
      return false if Abort()
      Progress.NextStep
      if Ops.get_boolean(@MailTransports, "Changed", false)
        # First we have to clean up TLS Sites
        if !YaPI::MailServer.WriteMailTransports(
            @MailTransports,
            @AdminPassword
          )
          Report.Error(_("Cannot write mail server transports."))
        end
      end
      Builtins.sleep(sl)

      # write mail preventions
      return false if Abort()
      Progress.NextStage
      if Ops.get_boolean(@MailPrevention, "VirusScanning", false)
        to_install = ""
        l_to_install = []
        if !@amavis_installed
          l_to_install = Builtins.add(l_to_install, "amavisd-new")
          to_install = Ops.add(to_install, "\n amavisd-new")
          if !@clamav_installed
            l_to_install = Builtins.add(l_to_install, "clamav")
            to_install = Ops.add(to_install, "\n clamav")
          end
          if !@spamassassin_installed
            l_to_install = Builtins.add(l_to_install, "spamassassin")
            to_install = Ops.add(to_install, "\n spamassassin")
          end
          if !@amavis_installed || !@clamav_installed ||
              !@spamassassin_installed
            if Report.AnyQuestion(
                "",
                Ops.add(
                  _("You have not installed all needed packages."),
                  to_install
                ),
                Label.InstallButton,
                Label.AbortButton,
                :focus_yes
              )
              Package.DoInstall(l_to_install)
              Builtins.y2milestone("Installing amavis")
            else
              return false
            end
            Service.Start("clamd")
            Service.Start("freshclam")
            Service.Start("amavis")
          end
          Service.Enable("amavis")
          Service.Enable("clamd")
          Service.Enable("freshclam")
        end
      end
      if Ops.get_boolean(@MailPrevention, "Changed", false)
        if !YaPI::MailServer.WriteMailPrevention(
            @MailPrevention,
            @AdminPassword
          )
          Report.Error(_("Cannot write mail server preventions."))
        end
        if Ops.get_boolean(@MailPrevention, "VirusScanning", false)
          Service.Enable("amavis")
          Service.Enable("clamd")
          Service.Enable("freshclam")
          Service.Restart("clamd")
          Service.Restart("freshclam")
          Service.Restart("amavis")
        else
          Service.Stop("clamd")
          Service.Stop("freshclam")
          Service.Stop("amavis")
          Service.Disable("amavis")
          Service.Disable("clamd")
          Service.Disable("freshclam")
        end
      end
      Builtins.sleep(sl)

      # write mail realaying
      return false if Abort()
      Progress.NextStage
      if Ops.get_boolean(@MailRelaying, "Changed", false)
        if !YaPI::MailServer.WriteMailRelaying(@MailRelaying, @AdminPassword)
          Report.Warning(_("Cannot write the mail server relay settings."))
        end
      end
      Builtins.sleep(sl)

      # write mail server fetching jobs
      return false if Abort()
      if Ops.get_list(@FetchingMail, "Items", []) != []
        Service.Enable("fetchmail")
        if !@fetchmail_installed
          if Report.AnyQuestion(
              "",
              _("You have not installed all needed packages.") + "\n fetchmail \n",
              Label.InstallButton,
              Label.AbortButton,
              :focus_yes
            )
            Package.DoInstall(["fetchmail"])
          else
            return false
          end
        end
      else
        Service.Disable("fetchmail") if @fetchmail_installed
      end
      Progress.NextStage
      if Ops.get_boolean(@FetchingMail, "Changed", false)
        if !YaPI::MailServer.WriteFetchingMail(@FetchingMail, @AdminPassword)
          Report.Warning(_("Cannot write the mail server fetching jobs."))
        end
        Service.Restart("fetchmail")
      end
      Builtins.sleep(sl)

      # write mail server local domains
      return false if Abort()
      Progress.NextStage
      if Ops.get_boolean(@MailLocalDomains, "Changed", false)
        if !YaPI::MailServer.WriteMailLocalDomains(
            @MailLocalDomains,
            @AdminPassword
          )
          Report.Warning(_("Cannot write the mail server domains."))
        end
      end
      Builtins.sleep(sl)

      Service.Restart("postfix") if Modified()

      return false if Abort()
      true
    end

    # Get all mail-server settings from the first parameter
    # (For use by autoinstallation.)
    # @param [Hash] settings The YCP structure to be imported.
    # @return [Boolean] True on success
    def Import(settings)
      settings = deep_copy(settings)
      # TODO FIXME: your code here (fill the above mentioned variables)...
      true
    end

    # Dump the mail-server settings to a single map
    # (For use by autoinstallation.)
    # @return [Hash] Dumped settings (later acceptable by Import ())
    def Export
      # TODO FIXME: your code here (return the above mentioned variables)...
      {}
    end

    # Create a textual summary and a list of unconfigured cards
    # @return summary of the current configuration
    def Summary
      # TODO FIXME: your code here...
      # Configuration summary text for autoyast
      [_("Configuration summary ..."), []]
    end

    # Create an overview table with all configured cards
    # @return table items
    def Overview
      # TODO FIXME: your code here...
      []
    end

    # Return packages needed to be installed and removed during
    # Autoinstallation to insure module has all needed software
    # installed.
    # @return [Hash] with 2 lists.
    def AutoPackages
      # TODO FIXME: your code here...
      { "install" => [], "remove" => [] }
    end

    publish :function => :Modified, :type => "boolean ()"
    publish :variable => :modified, :type => "boolean"
    publish :variable => :proposal_valid, :type => "boolean"
    publish :variable => :AbortFunction, :type => "boolean ()"
    publish :function => :Abort, :type => "boolean ()"
    publish :variable => :setup, :type => "boolean"
    publish :variable => :CertExist, :type => "boolean"
    publish :variable => :GlobalSettings, :type => "map <string, any>"
    publish :variable => :MailTransports, :type => "map <string, any>"
    publish :variable => :MailPrevention, :type => "map <string, any>"
    publish :variable => :MailRelaying, :type => "map <string, any>"
    publish :variable => :MailLocalDelivery, :type => "map <string, any>"
    publish :variable => :FetchingMail, :type => "map <string, any>"
    publish :variable => :MailLocalDomains, :type => "map <string, any>"
    publish :variable => :LDAPDefaults, :type => "map <string, any>"
    publish :variable => :PPPCards, :type => "list <string>"
    publish :variable => :AdminPassword, :type => "string"
    publish :variable => :ModulesTreeContent, :type => "list <list>"
    publish :variable => :pam_ldap_installed, :type => "boolean"
    publish :variable => :nss_ldap_installed, :type => "boolean"
    publish :variable => :procmail_installed, :type => "boolean"
    publish :variable => :ldap_installed, :type => "boolean"
    publish :variable => :imap_installed, :type => "boolean"
    publish :variable => :postfix_installed, :type => "boolean"
    publish :variable => :fetchmail_installed, :type => "boolean"
    publish :variable => :sasl_installed, :type => "boolean"
    publish :variable => :saslauthd_installed, :type => "boolean"
    publish :variable => :plugins_installed, :type => "boolean"
    publish :variable => :amavis_installed, :type => "boolean"
    publish :variable => :spamassassin_installed, :type => "boolean"
    publish :variable => :clamav_installed, :type => "boolean"
    publish :function => :CheckPackages, :type => "boolean ()"
    publish :function => :Read, :type => "boolean ()"
    publish :function => :Write, :type => "boolean ()"
    publish :function => :Import, :type => "boolean (map)"
    publish :function => :Export, :type => "map ()"
    publish :function => :Summary, :type => "list ()"
    publish :function => :Overview, :type => "list ()"
    publish :function => :AutoPackages, :type => "map ()"
  end

  MailServer = MailServerClass.new
  MailServer.main
end
