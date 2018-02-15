# encoding: utf-8

# File:
#   modules/Mail.ycp
#
# Package:
#   Configuration of mail
#
# Summary:
#   Data for configuration of mail, input and output functions.
#
# Authors:
#   Martin Vidner <mvidner@suse.cz>
#
# $Id$
#
# Representation of the configuration of mail.
# Input and output routines.
#
require "yast"
require "y2firewall/firewalld"

module Yast
  class MailClass < Module
    def main
      textdomain "mail"

      Yast.import "MailAliases"
      Yast.import "MailTable"
      Yast.import "Mode"
      Yast.import "Report"
      Yast.import "Service"
      Yast.import "Summary"
      Yast.import "Progress"
      Yast.import "Package"
      Yast.import "PackageSystem"

      # ----------------------------------------------------------------


      # Required packages
      @required_packages = []

      # `sendmail, `postfix or `other
      # Initialized by ReadMta
      @mta = nil

      @create_config = false

      # `permanent, `dialup or `none
      @connection_type = :permanent

      # If false, port 25 will listen only for localhost
      @listen_remote = false

      # Use a virus scanner (AMaViS).
      # amavisd-new (mta-independent) must be installed.
      # It will be installed if is not installed.
      @use_amavis = false

      # Use a DKIM for outgoing email.
      # If it is enabled AMaViS will be enabled too.
      @use_dkim = false


      # Domains for locally delivered mail.
      # (ahost.acompany.com is a domain)
      @local_domains = []

      # A relay server for outgoing mail.
      @outgoing_mail_server = ""

      # Shall be enclosed in [brackets] to prevent MX lookups.
      @outgoing_mail_server_nomx = true

      # Do the MTA use TLS for sending the email.
      @smtp_use_TLS = "yes"

      # Mail will appear to come from this domain. Applies also for the
      # envelope. Does not apply for mail from root.
      @from_header = ""

      # If empty, from_header will be applied to mails coming from
      # local_domains, otherwise from these domains. (Remember: mail
      # domains)
      @masquerade_other_domains = []

      # User specific sender masquerading.
      # List of maps: $[comment:, user:, address:] (all are strings)
      @masquerade_users = []

      # sysconfig/postfix:POSTFIX_MDA
      # #26052
      @postfix_mda = :local

      # When should fetchmail run:
      # <dl>
      # <dt> "manual"  <dd>
      # <dt> "daemon"  <dd>
      @fetchmail_mode = "manual"

      #List of maps:
      # $[server:, protocol:, remote_user:, local_user:, password:,
      # enabled:(bool), other_(server|client)_options: ]
      @fetchmail = []

      # Domain-specific aliases.
      # List of maps: $[comment:, alias:, destinations:] (all are strings)
      @virtual_users = []

      # SMTP AUTH (#23000)
      # list of maps:
      # The ui only handles the first list item, the rest is for autoyast
      # $[server: string, user: string, password: string(plain text)]
      # There are other map keys that must be preserved on editing.
      @smtp_auth = []

      # Sysconfig setting that enables the feature.
      # For postfix, it is a simple yes/no which we set to (size(smtp_auth)>0)
      # For sendmail, it is a list of methods which we set to empty or all
      # but we don't touch it if it was something in between, marked as nil.
      # Must default to non-nil.
      @enable_smtp_auth = false

      # Sysconfig setting which contains the email address which will
      # be applied as sender for system mails
      @system_mail_sender = ""

      # ----------------------------------------------------------------
      # constants

      # The full set of authentication mechanisms for sendmail
      @sendmail_all_mechanisms = "plain gssapi digest-md5 cram-md5" #const

      # Fetchmail protocols, as defined in rcfile_l.l
      # Probably not all of them are compatible with our simplified scheme
      # but it does not hurt to include them.
      # Must check for validity: the agent matches [[:alnum:]]+,
      # lowercase names are valid too.
      @protocol_choices = [
        "AUTO",
        "POP2",
        "POP3",
        "IMAP",
        "APOP",
        "KPOP",
        "SDPS",
        "ETRN",
        "ODMR"
      ]

      # ----------------------------------------------------------------

      # Has the configuration been changed?
      # Can be used as an argument to Popup::ReallyAbort
      @touched = false

      # ----------------------------------------------------------------

      # Read only, set by ProbePackages.
      # Use as an argument to Package::DoInstallAndRemove
      @install_packages = []
      # Read only, set by ProbePackages.
      # Use as an argument to Package::DoInstallAndRemove
      @remove_packages = []

      # Of the four available amavis packages, amavis-postfix does not need
      # a service running, others do.
      # Update: only one package, amavisd-new, but let's keep the variable,
      # just in case.
      # We query rpm in WriteGeneral (so that it works for autoinst too).
      # This is only used if use_amavis is on, of course.
      @amavis_service = true

      # The cron file name for the queue checking.
      @cron_file = "/etc/cron.d/novell.postfix-check-mail-queue"

      # The cron interval for the queue checking.
      @check_interval = 15
    end

    # If MAIL_CREATE_CONFIG is not yes, the user
    # does not want us to modify sendmail.cf/main.cf.
    # So we will warn him before setting it to yes.
    # @return	Is it yes?
    def CreateConfig
      @create_config
    end

    # A convenient shortcut for setting touched.
    # @param [Boolean] really	if true, set Mail::touched
    # @example Mail::Touch (Mail::var != ui_var);
    def Touch(really)
      @touched = @touched || really

      nil
    end

    # Detect which packages have to be installed
    # and return a descriptive string for a plain text pop-up.
    # @return "" or "Foo will be installed.\nBar will be installed.\n"
    def ProbePackages
      message = ""
      newimap = false
      @install_packages = []
      @remove_packages = []

      if @use_amavis
        pkg = "amavisd-new"
        if !Package.Installed(pkg)
          @install_packages = Builtins.add(@install_packages, pkg)
          # Translators: popup message part, ends with a newline
          message = Ops.add(
            message,
            _("AMaViS, a virus scanner, will be installed.\n")
          )
        end

        if !Package.Installed("spamassassin")
          #If spamassassin is not installaed amavisd can not work
          @install_packages = Builtins.add(@install_packages, "spamassassin")
          # Translators: popup message part, ends with a newline
          message = Ops.add(
            message,
            _("SpamAssassin will be installed.\n")
          )
	end
        if !Package.Installed("clamav")
          # #115295
          # Amavis alone will block incoming mail if no scanner is found
          # We ship clamav but not on opensuse
          # Clamav can work without clamav-db.rpm if set up manually
          # so we do not check Installed "clamav-db"
          Builtins.y2milestone("clamav not installed")
          if !Package.AvailableAll(["clamav", "clamav-db"])
            # error popup.
            Report.Error(
              _(
                "AMaViS needs a virus scanner such as ClamAV\n" +
                  "to do the actual scanning, but ClamAV was not found.\n" +
                  "Configure a scanner manually."
              )
            )
          else
            @install_packages = Builtins.add(@install_packages, "clamav")
            @install_packages = Builtins.add(@install_packages, "clamav-db")
          end
        end
      end

      if Ops.greater_than(Builtins.size(@fetchmail), 0) &&
          !Package.Installed("fetchmail")
        @install_packages = Builtins.add(@install_packages, "fetchmail")
        # Translators: popup message part, ends with a newline
        message = Ops.add(
          message,
          _("Fetchmail, a mail downloading utility, will be installed.\n")
        )
      end

      if @postfix_mda == :imap && !Package.Installed("dovecot")
        @install_packages = Builtins.add(@install_packages, "dovecot")
        # Translators: popup message part, ends with a newline
        message = Ops.add(
          message,
          _("Dovecot IMAP server, will be installed.\n")
        )
        newimap = true
      end
      Package.DoInstall(@install_packages) if @install_packages != []
      if newimap
        Service.Enable("dovecot")
        Service.Start("dovecot")
      end
      message
    end

    # ----------------------------------------------------------------

    # Detect the MTA installed
    def ReadMta
      # so that AY cloning works, #45071
      Builtins.y2milestone("========== Reading MTA ==========")
      if PackageSystem.Installed("sendmail")
        @mta = :sendmail
      elsif PackageSystem.Installed("postfix")
        @mta = :postfix
      else
        @mta = :other
      end
      Builtins.y2milestone("Read MTA: %1", @mta)

      nil
    end

    # @return Whether rcfetchmail should run
    def RunFetchmailGlobally
      @fetchmail_mode == "daemon" &&
        Ops.greater_than(Builtins.size(@fetchmail), 0)
    end

    # Read all mail settings from the SCR
    # @param [Proc] abort A block that can be called by Read to find
    #	      out whether abort is requested. Returns true if abort
    #	      was pressed.
    # @return True on success
    def Read(abort)
      abort = deep_copy(abort)
      # Translators: dialog caption
      caption = _("Initializing mail configuration")

      Progress.New(
        caption,
        " ",
        0,
        [
          # Translators: progress label
          # do not translate MTA
          _("Determining Mail Transport Agent (MTA)"),
          # Translators: progress label
          _("Reading general settings"),
          # Translators: progress label
          _("Reading masquerading settings"),
          # Translators: progress label
          _("Reading downloading settings"),
          # Translators: progress label
          _("Reading alias tables"),
          # Translators: progress label
          # smtp-auth
          _("Reading authentication settings...")
        ],
        [],
        ""
      )

      # announce 1
      Progress.NextStage
      return false if Builtins.eval(abort)
      # read 1
      ReadMta()
      return false if @mta == :other

      # announce 2
      Progress.NextStage
      return false if Builtins.eval(abort)
      # read 2
      # create_config
      @create_config = SCR.Read(path(".sysconfig.mail.MAIL_CREATE_CONFIG")) == "yes"

      # open port
      @listen_remote = SCR.Read(path(".sysconfig.mail.SMTPD_LISTEN_REMOTE")) == "yes"
      Y2Firewall::Firewalld.instance.read

      # connection_type:
      nc = false
      ex = false
      nd = false
      # the service must be always running
      #boolean service = false;
      if @mta == :sendmail
        nc = SCR.Read(path(".sysconfig.sendmail.SENDMAIL_NOCANONIFY")) == "yes"
        ex = SCR.Read(path(".sysconfig.sendmail.SENDMAIL_EXPENSIVE")) == "yes"
      elsif @mta == :postfix
        nc = SCR.Read(path(".sysconfig.postfix.POSTFIX_NODNS")) == "yes"
        ex = SCR.Read(path(".sysconfig.postfix.POSTFIX_DIALUP")) == "yes"
        nd = ! Service.Enabled("postfix")
      else
        return false
      end
      if nd
        @connection_type = :nodaemon
      elsif nc
        @connection_type = ex ? :dialup : :none
      else
        @connection_type = :permanent
      end

      # amavis
      @use_amavis = SCR.Read(path(".sysconfig.amavis.USE_AMAVIS")) == "yes"
      @use_dkim = @use_amavis &&
        SCR.Read(path(".sysconfig.amavis.USE_DKIM")) == "yes"

      # local_domains
      ld_s = ""
      if @mta == :sendmail
        ld_s = Convert.to_string(
          SCR.Read(path(".sysconfig.sendmail.SENDMAIL_LOCALHOST"))
        )
      elsif @mta == :postfix
        ld_s = Convert.to_string(
          SCR.Read(path(".sysconfig.postfix.POSTFIX_LOCALDOMAINS"))
        )
      else
        return false
      end
      @local_domains = Builtins.filter(Builtins.splitstring(ld_s, " ,;")) do |s|
        s != ""
      end

      # outgoing_mail_server
      if @mta == :sendmail
        @outgoing_mail_server = Convert.to_string(
          SCR.Read(path(".sysconfig.sendmail.SENDMAIL_SMARTHOST"))
        )
      elsif @mta == :postfix
        @smtp_use_TLS = Convert.to_string(
          SCR.Read(path(".sysconfig.postfix.POSTFIX_SMTP_TLS_CLIENT"))
        )
        @outgoing_mail_server = Convert.to_string(
          SCR.Read(path(".sysconfig.postfix.POSTFIX_RELAYHOST"))
        )
	if @outgoing_mail_server.length > 0 and @outgoing_mail_server.delete!("[]") == nil
	   @outgoing_mail_server_nomx = false
	end
      else
        return false
      end

      # postfix_mda
      if @mta == :postfix
        postfix_mda_s = Convert.to_string(
          SCR.Read(path(".sysconfig.postfix.POSTFIX_MDA"))
        )
        if postfix_mda_s == "local"
          @postfix_mda = :local
        elsif postfix_mda_s == "procmail"
          @postfix_mda = :procmail
        elsif postfix_mda_s == "imap"
          @postfix_mda = :imap
        else
          @postfix_mda = nil
        end
      end

      # announce 3
      Progress.NextStage
      return false if Builtins.eval(abort)
      # read 3
      # from_header
      @from_header = Convert.to_string(
        SCR.Read(path(".sysconfig.mail.FROM_HEADER"))
      )
      # handle nonexistent file
      @from_header = "" if @from_header == nil

      # masquerade_other_domains
      mod_s = ""
      if @mta == :sendmail
        mod_s = Convert.to_string(
          SCR.Read(path(".sysconfig.sendmail.MASQUERADE_DOMAINS"))
        )
      elsif @mta == :postfix
        mod_s = Convert.to_string(
          SCR.Read(path(".sysconfig.postfix.POSTFIX_MASQUERADE_DOMAIN"))
        )
      else
        return false
      end
      @masquerade_other_domains = Builtins.filter(
        Builtins.splitstring(mod_s, " ,;")
      ) { |s| s != "" }

      # masquerade_users
      mu_raw = []
      if @mta == :sendmail
        mu_raw = MailTable.Read("sendmail.generics")
      elsif @mta == :postfix
        mu_raw = MailTable.Read("postfix.sendercanonical")
      else
        return false
      end
      @masquerade_users = Builtins.maplist(mu_raw) do |e|
        {
          "comment" => Ops.get_string(e, "comment", ""),
          "user"    => Ops.get_string(e, "key", ""),
          "address" => Ops.get_string(e, "value", "")
        }
      end

      # announce 4
      Progress.NextStage
      return false if Builtins.eval(abort)
      @fetchmail_mode = "daemon" if Service.Enabled("fetchmail")

      # if we are testing as non-root, it will fail, that's OK
      out = Convert.to_map(
        SCR.Execute(path(".target.bash_output"), "/usr/bin/id --user")
      )
      root = Ops.get_string(out, "stdout", "") == "0\n"

      @fetchmail = Convert.convert(
        SCR.Read(path(".mail.fetchmail.accounts")),
        :from => "any",
        :to   => "list <map>"
      )
      if @fetchmail == nil && root
        # Translators: error message,
        # %1 is a file name,
        # %2 is a long file name - leave it on a separate line
        Report.Error(
          Builtins.sformat(
            _(
              "Error reading file %1. The file must have\n" +
                "a fixed format to be readable by YaST.  For details, see\n" +
                "%2"
            ),
            "/etc/fetchmailrc",
            "/usr/share/doc/packages/yast2-mail/fetchmailrc.txt"
          )
        )
        return false
      end
      #TODO what to do with a difficult syntax etc?

      # announce 5
      Progress.NextStage
      return false if Builtins.eval(abort)
      # read 5
      #	MailAliases::merge_aliases = false;

      # aliases
      return false if !MailAliases.ReadAliases
      # virtual_users
      v_raw = []
      if @mta == :sendmail
        v_raw = MailTable.Read("sendmail.virtuser")
      elsif @mta == :postfix
        v_raw = MailTable.Read("postfix.virtual")
      else
        return false
      end
      @virtual_users = Builtins.maplist(v_raw) do |e|
        {
          "comment"      => Ops.get_string(e, "comment", ""),
          "alias"        => Ops.get_string(e, "key", ""),
          "destinations" => Ops.get_string(e, "value", "")
        }
      end

      # announce 6
      Progress.NextStage
      return false if Builtins.eval(abort)
      # read 6
      if @mta == :sendmail
        @smtp_auth = Convert.convert(
          SCR.Read(path(".mail.sendmail.auth.accounts")),
          :from => "any",
          :to   => "list <map>"
        )
        mechanisms = Convert.to_string(
          SCR.Read(path(".sysconfig.sendmail.SMTP_AUTH_MECHANISMS"))
        )
        if mechanisms != @sendmail_all_mechanisms && mechanisms != ""
          @enable_smtp_auth = nil
        end
      elsif @mta == :postfix
        @smtp_auth = Convert.convert(
          SCR.Read(path(".mail.postfix.auth.accounts")),
          :from => "any",
          :to   => "list <map>"
        )
      else
        return false
      end


      # complete
      Progress.NextStage
      true
    end

    # Wrapper for global Read function, without the callback argument
    def ReadWithoutCallback
      abort_block = lambda { false }
      Read(abort_block)
    end

    # Make up data for screnshots
    def Fake
      @mta = :postfix
      @create_config = true
      @listen_remote = true
      @connection_type = :dialup
      @use_amavis = true
      @use_dkim = true
      # good example?
      @local_domains = ["branch1.example.com", "branch2.example.com"]
      @outgoing_mail_server = "mail.example.com"
      @outgoing_mail_server_nomx = true
      @from_header = "example.com"
      @masquerade_other_domains = []
      @masquerade_users = [
        { "user" => "hyde", "address" => "DrJekyll@Example.com" }
      ]
      @fetchmail = [
        {
          "server"      => "pop3.example.net",
          "protocol"    => "POP3",
          "remote_user" => "jekyll",
          "local_user"  => "hyde",
          "password"    => "stephenson"
        }
      ]

      # just patch out root
      MailAliases.ReadAliases
      MailAliases.root_alias = "hyde"

      # TODO virtual
      @enable_smtp_auth = true
      @smtp_auth = [
        {
          "server"   => "mail.example.com",
          "user"     => "jekyll",
          "password" => "foo"
        }
      ]

      nil
    end

    # Part of Write.
    # @return success
    def WriteGeneral
      # create_config
      # if the user wanted it false, we did not proceed
      SCR.Write(path(".sysconfig.mail.MAIL_CREATE_CONFIG"), "yes")
      # listen_remote
      SCR.Write(
        path(".sysconfig.mail.SMTPD_LISTEN_REMOTE"),
        @listen_remote ? "yes" : "no"
      )
      Y2Firewall::Firewalld.instance.write_only

      # connection_type
      # nocanonify/nodns
      # expensive/dialup
      nc_nd = nil
      ex_di = nil
      service = nil
      if @mta == :sendmail
        nc_nd = path(".sysconfig.sendmail.SENDMAIL_NOCANONIFY")
        ex_di = path(".sysconfig.sendmail.SENDMAIL_EXPENSIVE")
        service = "sendmail"
      elsif @mta == :postfix
        nc_nd = path(".sysconfig.postfix.POSTFIX_NODNS")
        ex_di = path(".sysconfig.postfix.POSTFIX_DIALUP")
        service = "postfix"
      else
        return false
      end

      if @connection_type == :nodaemon
        SCR.Write(nc_nd, "yes")
        SCR.Write(ex_di, "no")
      elsif @connection_type == :permanent
        SCR.Write(nc_nd, "no")
        SCR.Write(ex_di, "no")
      elsif @connection_type == :dialup
        SCR.Write(nc_nd, "yes")
        SCR.Write(ex_di, "yes")
      elsif @connection_type == :none
        SCR.Write(nc_nd, "yes")
        SCR.Write(ex_di, "no")
      else
        Builtins.y2internal(
          "Unrecognized connection_type: %1",
          @connection_type
        )
        return false
      end
      if @connection_type == :nodaemon
        Service.Disable(service)
        SCR.Write(path(".sysconfig.amavis.USE_AMAVIS"), "no")
        SCR.Write(
          path(".target.string"),
          @cron_file,
          Ops.add(
            Ops.add("-*/", @check_interval),
            " * * * * root /usr/sbin/check_mail_queue &>/dev/null"
          )
        )
      else
        SCR.Execute(
          path(".target.bash"),
          Ops.add(
            Ops.add(
              Ops.add(Ops.add("test -e ", @cron_file), "  && rm "),
              @cron_file
            ),
            ";"
          )
        )
        Service.Enable(service)
        Service.Adjust("amavis", @use_amavis ? "enable" : "disable")
      end

      # amavis
      SCR.Write(
        path(".sysconfig.amavis.USE_AMAVIS"),
        @use_amavis ? "yes" : "no"
      )
      SCR.Write(path(".sysconfig.amavis.USE_DKIM"), @use_dkim ? "yes" : "no")
      # used also in WriteServices
      @amavis_service = true
      Service.Adjust("amavis", @use_amavis ? "enable" : "disable")

      # SENDMAIL_ARGS
      # by default they contain -q30m, not good for dial-up
      # SENDMAIL_CLIENT_ARGS must contain -q... or it will not run!
      if @mta == :sendmail
        default_permanent = "-L sendmail -Am -bd -q30m -om"
        default_dialup = "-L sendmail -Am -bd -om"
        args = Convert.to_string(
          SCR.Read(path(".sysconfig.sendmail.SENDMAIL_ARGS"))
        )

        if @connection_type == :permanent && args == default_dialup
          SCR.Write(
            path(".sysconfig.sendmail.SENDMAIL_ARGS"),
            default_permanent
          )
        elsif @connection_type == :dialup &&
            # if empty, sendmail init-script uses the default
            (args == default_permanent || args == "")
          SCR.Write(path(".sysconfig.sendmail.SENDMAIL_ARGS"), default_dialup)
        end
      end

      # local_domains
      if @mta == :sendmail
        ld_s = Builtins.mergestring(@local_domains, " ")
        SCR.Write(path(".sysconfig.sendmail.SENDMAIL_LOCALHOST"), ld_s)
      elsif @mta == :postfix
        ld_s = Builtins.mergestring(@local_domains, ",") # noted in #12672
        SCR.Write(path(".sysconfig.postfix.POSTFIX_LOCALDOMAINS"), ld_s)
      else
        return false
      end

      # outgoing_mail_server
      if @mta == :sendmail
        SCR.Write(
          path(".sysconfig.sendmail.SENDMAIL_SMARTHOST"),
          @outgoing_mail_server
        )
      elsif @mta == :postfix
	if Mode.mode != "autoinstallation"
           @outgoing_mail_server.delete("[]")
           if @outgoing_mail_server_nomx
             l_oms = @outgoing_mail_server.split(/:/)
             if l_oms.length == 2
                @outgoing_mail_server = "[" + l_oms[0] + "]" + ":" + l_oms[1]
             elsif l_oms.length == 1
                @outgoing_mail_server = "[" + l_oms[0] + "]"
             end
           end
	end
        SCR.Write(
          path(".sysconfig.postfix.POSTFIX_RELAYHOST"),
          @outgoing_mail_server
        )
        SCR.Write(
          path(".sysconfig.postfix.POSTFIX_SMTP_TLS_CLIENT"),
          @smtp_use_TLS
        )
      else
        return false
      end

      # postfix_mda
      if @mta == :postfix
        s_mda = "local" # default to local
        if @postfix_mda == :procmail
          s_mda = "procmail"
        elsif @postfix_mda == :imap
          s_mda = "imap"
        end
        SCR.Write(path(".sysconfig.postfix.POSTFIX_MDA"), s_mda)
      end
      true
    end

    # Part of Write.
    # @return success
    def WriteMasquerading
      # from_header
      SCR.Write(path(".sysconfig.mail.FROM_HEADER"), @from_header)
      # masquerade_other_domains
      if @mta == :sendmail
        mod = Builtins.mergestring(@masquerade_other_domains, " ")
        SCR.Write(path(".sysconfig.sendmail.MASQUERADE_DOMAINS"), mod)
      elsif @mta == :postfix
        mod = Builtins.mergestring(@masquerade_other_domains, ",")
        SCR.Write(path(".sysconfig.postfix.POSTFIX_MASQUERADE_DOMAIN"), mod)
      else
        return false
      end

      # masquerade_users
      mu_raw = Builtins.maplist(@masquerade_users) do |e|
        {
          "comment" => Ops.get_string(e, "comment", ""),
          # TODO check that nonempty
          "key"     => Ops.get_string(e, "user", ""),
          "value"   => Ops.get_string(e, "address", "")
        }
      end
      if @mta == :sendmail
        MailTable.Write("sendmail.generics", mu_raw)
      elsif @mta == :postfix
        MailTable.Write("postfix.sendercanonical", mu_raw)
      else
        return false
      end
      true
    end

    # Part of Write.
    # @return success
    def WriteDownloading
      # fetchmail
      # TODO ?other settings: autofetch? at device up?
      SCR.Write(path(".mail.fetchmail.accounts"), @fetchmail)
      if !SCR.Write(path(".mail.fetchmail"), nil)
        # Translators: error message
        Report.Error(_("Error writing the fetchmail configuration."))
        return false
      end

      if RunFetchmailGlobally()
        Service.Enable("fetchmail")
      else
        Service.Disable("fetchmail")
      end
      true
    end

    # Part of Write.
    # @return success
    def WriteAliasesAndVirtual
      # aliases
      return false if !MailAliases.WriteAliases

      # virtual_users
      v_raw = Builtins.maplist(@virtual_users) do |e|
        {
          "comment" => Ops.get_string(e, "comment", ""),
          "key"     => Ops.get_string(e, "alias", ""),
          "value"   => Ops.get_string(e, "destinations", "")
        }
      end
      if @mta == :sendmail
        MailTable.Write("sendmail.virtuser", v_raw)
      elsif @mta == :postfix
        MailTable.Write("postfix.virtual", v_raw)
      else
        return false
      end
      true
    end

    # Part of Write.
    # @return success
    def WriteSmtpAuth
      # TODO how to remove the only entry?
      # filter it out in the dialog?
      if @enable_smtp_auth != nil
        @enable_smtp_auth = Ops.greater_than(Builtins.size(@smtp_auth), 0)
      end
      if Ops.get_string(@smtp_auth, [0, "server"], "") != @outgoing_mail_server
        Ops.set(@smtp_auth, [0, "server"], @outgoing_mail_server)
      end
      if @mta == :sendmail
        SCR.Write(path(".mail.sendmail.auth.accounts"), @smtp_auth)
        if @enable_smtp_auth != nil
          SCR.Write(
            path(".sysconfig.sendmail.SMTP_AUTH_MECHANISMS"),
            @enable_smtp_auth ? @sendmail_all_mechanisms : ""
          )
        end
      elsif @mta == :postfix
        SCR.Write(path(".mail.postfix.auth.accounts"), @smtp_auth)
        SCR.Write(
          path(".sysconfig.postfix.POSTFIX_SMTP_AUTH"),
          @enable_smtp_auth ? "yes" : "no"
        )
      else
        return false
      end
      true
    end

    # Part of Write.
    # @return success
    def WriteFlush
      #flush the agents
      paths = {
        "/etc/sysconfig/mail"   => path(".sysconfig.mail"),
        "/etc/sysconfig/amavis" => path(".sysconfig.amavis")
      }
      tables = nil

      if @mta == :sendmail
        Ops.set(paths, "/etc/sysconfig/sendmail", path(".sysconfig.sendmail"))
        Ops.set(paths, "/etc/mail/auth/auth-info", path(".mail.sendmail.auth"))
        tables = ["sendmail.generics", "aliases", "sendmail.virtuser"]
      elsif @mta == :postfix
        Ops.set(paths, "/etc/sysconfig/postfix", path(".sysconfig.postfix"))
        Ops.set(paths, "/etc/postfix/sasl_passwd", path(".mail.postfix.auth"))
        tables = ["postfix.sendercanonical", "aliases", "postfix.virtual"]
      else
        return false
      end

      Builtins.foreach(paths) do |filename, p|
        if !SCR.Write(p, nil)
          # Translators: error message
          Report.Error(Builtins.sformat(_("Error writing file %1"), filename))
          next false
        end
      end

      Builtins.foreach(tables) do |p|
        if !MailTable.Flush(p)
          filename = MailTable.FileName(p)
          # Translators: error message
          Report.Error(Builtins.sformat(_("Error writing file %1"), filename))
          next false
        end
      end
      true
    end

    # Part of Write.
    # @return success
    def WriteConfig
      ret = 0
      if @mta == :postfix
        ret = Convert.to_integer(
          SCR.Execute(path(".target.bash"), "/usr/sbin/config.postfix")
        )
      else
        return false
      end

      if ret != 0
        # Translators: error message
        Report.Error(_("Error running config.postfix"))
        return false
      end
      true
    end

    # Part of Write.
    # @return success
    def WriteServices
      if @amavis_service
        Service.Stop("amavis")
        if @use_amavis
          SCR.Execute(path(".target.bash_output"), "test -e /etc/mail/spamassassin/sa-update-keys/ || /usr/bin/sa-update")
          if !Service.Start("amavis")
            # Translators: error message
            Report.Error(
              Builtins.sformat(_("Error starting service %1."), "amavis")
            )
            return false
          end
        end
        if @use_dkim
          SCR.Execute(
            path(".target.bash"),
            "/usr/lib/YaST2/servers_non_y2/setup_dkim_verifying.pl"
          )
        end
      end

      Service.Stop("fetchmail")
      if RunFetchmailGlobally()
        if !Service.Start("fetchmail")
          # Translators: error message
          Report.Error(
            Builtins.sformat(_("Error starting service %1."), "fetchmail")
          )
          return false
        end
      end

      service = ""
      if @mta == :sendmail
        service = "sendmail"
      elsif @mta == :postfix
        service = "postfix"
      else
        return false
      end

      if !Service.Restart(service)
        # Translators: error message
        Report.Error(Builtins.sformat(_("Error starting service %1."), service))
        return false
      end

      # ServiceAdjust enable/disable is done in WriteGeneral
      Y2Firewall::Firewalld.instance.reload
    end

    # Update the SCR according to mail settings
    # @param [Proc] abort A block that can be called by Write to find
    #	      out whether abort is requested. Returns true if abort
    #	      was pressed.
    # @return True on success
    def Write(abort)
      abort = deep_copy(abort)
      stages = [
        # Translators: progress label
        [
          _("Writing general settings"),
          fun_ref(method(:WriteGeneral), "boolean ()")
        ]
      ]
      if @connection_type != :none
        # Translators: progress label
        stages = Builtins.add(
          stages,
          [
            _("Writing masquerading settings"),
            fun_ref(method(:WriteMasquerading), "boolean ()")
          ]
        )
        # Translators: progress label
        stages = Builtins.add(
          stages,
          [
            _("Writing alias tables"),
            fun_ref(method(:WriteAliasesAndVirtual), "boolean ()")
          ]
        )
        # Write them unconditionally, because it is now possible to
        # enter them also in the Permanent mode. Bug #17417.
        # Translators: progress label
        if Ops.greater_than(Builtins.size(@fetchmail), 0) ||
            Package.Installed("fetchmail")
          stages = Builtins.add(
            stages,
            [
              _("Writing downloading settings"),
              fun_ref(method(:WriteDownloading), "boolean ()")
            ]
          )
        end

        # Translators: progress label
        stages = Builtins.add(
          stages,
          [
            _("Writing authentication settings..."),
            fun_ref(method(:WriteSmtpAuth), "boolean ()")
          ]
        )
      end
      # Translators: progress label
      stages = Builtins.add(
        stages,
        [
          _("Finishing writing configuration files"),
          fun_ref(method(:WriteFlush), "boolean ()")
        ]
      )
      # Translators: progress label
      stages = Builtins.add(
        stages,
        [
          _("Running Config Postfix"),
          fun_ref(method(:WriteConfig), "boolean ()")
        ]
      )

      # Translators: progress label
      if Mode.mode() == "normal"
         stages = Builtins.add(
           stages,
           [
             _("Restarting services"),
             fun_ref(method(:WriteServices), "boolean ()")
           ]
         )
      end

      # Translators: dialog caption
      caption = _("Saving mail configuration")
      # We do not set help text here, because it was set outside
      Progress.New(caption, " ", 0, Builtins.maplist(stages) do |e|
        Ops.get_string(e, 0, "")
      end, [], "")

      Builtins.foreach(stages) do |e|
        Progress.NextStage
        if Builtins.eval(abort)
          # TODO: finishes only this iteration, not the function
          next false
        end
        af = Ops.get(e, 1)
        f = Convert.convert(af, :from => "any", :to => "boolean ()")
        if !f.call
          # TODO: finishes only this iteration, not the function
          next false
        end
      end

      # complete
      Progress.NextStage
      true
    end

    # Wrapper for global Write function, without the callback argument
    def WriteWithoutCallback
      abort_block = lambda { false }
      Write(abort_block)
    end

    # Get all mail settings from the first parameter
    # (For use by autoinstallation.)
    # @param [Hash] Settings The YCP structure to be imported.
    # @return True on success
    def Import(_Settings)
      _Settings = deep_copy(_Settings)
      settings = Convert.convert(
        _Settings,
        :from => "map",
        :to   => "map <string, any>"
      )

      Builtins.y2debug("before %1", settings) # may contain passwords
      settings = Builtins.mapmap(settings) do |k, v|
        if k == "mta" && Ops.is_symbol?(v)
          next { k => v }
        elsif k == "connection_type" && Ops.is_symbol?(v)
          next { k => v }
        elsif k == "postfix_mda" && Ops.is_symbol?(v)
          next { k => v }
        end
        if k == "mta" && v == "sendmail"
          next { "mta" => :sendmail }
        elsif k == "mta" && v == "postfix"
          next { "mta" => :postfix }
        elsif k == "mta"
          next { "mta" => :other }
        elsif k == "connection_type" && v == "permanent"
          next { "connection_type" => :permanent }
        elsif k == "connection_type" && v == "dialup"
          next { "connection_type" => :dialup }
        elsif k == "connection_type"
          next { "connection_type" => :none }
        elsif k == "postfix_mda" && v == "local"
          next { "postfix_mda" => :local }
        elsif k == "postfix_mda" && v == "procmail"
          next { "postfix_mda" => :procmail }
        elsif k == "postfix_mda"
          next { "postfix_mda" => :imap }
        else
          next { k => v }
        end
      end

      @mta = Ops.get_symbol(settings, "mta", :other)
      @connection_type = Ops.get_symbol(settings, "connection_type", :none)
      @listen_remote = Ops.get_boolean(settings, "listen_remote", false)
      @use_amavis = Ops.get_boolean(settings, "use_amavis", false)
      @use_dkim = Ops.get_boolean(settings, "use_dkim", false)
      @local_domains = Ops.get_list(settings, "local_domains", [])
      @outgoing_mail_server = Ops.get_string(
        settings,
        "outgoing_mail_server",
        ""
      )
      @postfix_mda = Ops.get_symbol(settings, "postfix_mda", :local)
      @from_header = Ops.get_string(settings, "from_header", "")
      @masquerade_other_domains = Ops.get_list(
        settings,
        "masquerade_other_domains",
        []
      )
      @masquerade_users = Ops.get_list(settings, "masquerade_users", [])
      @fetchmail = Ops.get_list(settings, "fetchmail", [])
      MailAliases.aliases = Ops.get_list(settings, "aliases", [])
      MailAliases.FilterRootAlias
      @virtual_users = Ops.get_list(settings, "virtual_users", [])
      @smtp_use_TLS = Ops.get_string(settings, "smtp_use_TLS", "yes")
      @smtp_auth = Ops.get_list(settings, "smtp_auth", [])
      @system_mail_sender = Ops.get_string(settings, "system_mail_sender", "")
      @use_amavis = true if @use_dkim
      Builtins.y2debug("after %1", settings) # may contain passwords
      true
    end


    # Dump the mail settings to a single map
    # (For use by autoinstallation.)
    # @return Dumped settings (later acceptable by Import ())
    def Export
      settings = {
        "mta"                      => @mta,
        "connection_type"          => @connection_type,
        "listen_remote"            => @listen_remote,
        "use_amavis"               => @use_amavis,
        "use_dkim"                 => @use_dkim,
        "local_domains"            => @local_domains,
        "outgoing_mail_server"     => @outgoing_mail_server,
        "from_header"              => @from_header,
        "masquerade_other_domains" => @masquerade_other_domains,
        "masquerade_users"         => @masquerade_users,
        "fetchmail"                => @fetchmail,
        "aliases"                  => MailAliases.MergeRootAlias(
          MailAliases.aliases
        ),
        #	    "merge_aliases": MailAliases::merge_aliases,
        "virtual_users"            => @virtual_users,
        "smtp_auth"                => @smtp_auth,
        "smtp_use_TLS"             => @smtp_use_TLS,
        "system_mail_sender"       => @system_mail_sender
      }
      if @mta == :postfix
        settings = Builtins.add(settings, "postfix_mda", @postfix_mda)
      end
      # Dont export empty fields
      Builtins.foreach(settings) do |k, v|
        if Builtins.contains(["", nil, [], {}], v)
          settings = Builtins.remove(settings, k)
        end
      end
      deep_copy(settings)
    end

    # Summarizes a list of data
    # @param [String] title passed to Summary::AddHeader
    # @param [Object] value a list (of scalars, lists or maps)
    # @param [Object] index if the entries are not scalars,
    #   use this index to get a scalar
    # @return Summary-formatted description
    def ListItem(title, value, index)
      value = deep_copy(value)
      index = deep_copy(index)
      summary = ""
      summary = Summary.AddHeader(summary, title)
      if Ops.is_list?(value) && value != nil && value != []
        summary = Summary.OpenList(summary)
        Builtins.foreach(Convert.to_list(value)) do |d|
          entry = ""
          if Ops.is_map?(d)
            entry = Ops.get_string(Convert.to_map(d), index, "???")
          elsif Ops.is_list?(d)
            entry = Ops.get_string(
              Convert.to_list(d),
              Convert.to_integer(index),
              "???"
            )
          else
            entry = Convert.to_string(d)
          end
          summary = Summary.AddListItem(summary, entry)
        end
        summary = Summary.CloseList(summary)
      else
        summary = Summary.AddLine(summary, Summary.NotConfigured)
      end
      summary
    end

    # Summary
    # @return [String] with summary of configuration
    def Summary
      # TODO: use widget captions, strip sho&rtcuts

      agent = ""
      if @mta == :sendmail
        # MTA used: Sendmail
        # Not translated
        agent = "Sendmail"
      elsif @mta == :postfix
        # MTA used: Postfix
        # Not translated
        agent = "Postfix"
      else
        # MTA used: other than Sendmail or Postfix
        agent = _("Other")
      end


      con_type = ""
      if @connection_type == :permanent
        # summary: connection type
        con_type = _("Permanent")
      elsif @connection_type == :dialup
        # summary: connection type
        con_type = _("Dial-up")
      else
        # summary: connection type
        con_type = _("None")
      end

      nc = Summary.NotConfigured
      summary = ""
      # summary header; mail transfer agent
      summary = Summary.AddHeader(summary, _("MTA"))
      summary = Summary.AddLine(summary, agent)
      # summary header
      summary = Summary.AddHeader(summary, _("Connection Type"))
      summary = Summary.AddLine(summary, con_type)

      # summary header
      summary = Summary.AddHeader(summary, _("Outgoing Mail Server"))
      summary = Summary.AddLine(
        summary,
        @outgoing_mail_server != "" ? @outgoing_mail_server : nc
      )

      # summary header; the "From: foo@bar.com" mail header
      summary = Summary.AddHeader(summary, _("From Header"))
      summary = Summary.AddLine(summary, @from_header != "" ? @from_header : nc)

      # summary item
      summary = Ops.add(
        summary,
        ListItem(_("Local Domains"), @local_domains, nil)
      )
      # summary item
      summary = Ops.add(
        summary,
        ListItem(_("Masquerade Other Domains"), @masquerade_other_domains, nil)
      )
      # summary item
      summary = Ops.add(
        summary,
        ListItem(_("Masquerade Users"), @masquerade_users, "user")
      )
      # summary header
      summary = Summary.AddHeader(summary, _("Accept remote SMTP connections"))
      summary = Summary.AddLine(summary, @listen_remote ? _("Yes") : _("No"))
      # summary header
      summary = Summary.AddHeader(summary, _("Use AMaViS"))
      summary = Summary.AddLine(summary, @use_amavis ? _("Yes") : _("No"))
      # summary header
      summary = Summary.AddHeader(summary, _("Use DKIM"))
      summary = Summary.AddLine(summary, @use_dkim ? _("Yes") : _("No"))
      # summary item
      summary = Ops.add(summary, ListItem(_("Fetchmail"), @fetchmail, "server"))
      # summary item
      summary = Ops.add(
        summary,
        ListItem(
          _("Aliases"),
          MailAliases.MergeRootAlias(MailAliases.aliases),
          "alias"
        )
      )
      # summary item
      summary = Ops.add(
        summary,
        ListItem(_("Virtual Users"), @virtual_users, "alias")
      )
      # summary item
      summary = Ops.add(
        summary,
        ListItem(_("Authentication"), @smtp_auth, "server")
      )
      summary
    end

    # Return required packages for auto-installation
    # @return [Hash] of packages to be installed and to be removed
    def AutoPackages
      { "install" => @required_packages, "remove" => [] }
    end

    publish :variable => :required_packages, :type => "list"
    publish :variable => :mta, :type => "symbol"
    publish :variable => :outgoing_mail_server_nomx, :type => "boolean"
    publish :variable => :write_only, :type => "boolean"
    publish :variable => :connection_type, :type => "symbol"
    publish :variable => :listen_remote, :type => "boolean"
    publish :variable => :use_amavis, :type => "boolean"
    publish :variable => :use_dkim, :type => "boolean"
    publish :variable => :local_domains, :type => "list <string>"
    publish :variable => :outgoing_mail_server, :type => "string"
    publish :variable => :smtp_use_TLS, :type => "string"
    publish :variable => :from_header, :type => "string"
    publish :variable => :masquerade_other_domains, :type => "list <string>"
    publish :variable => :masquerade_users, :type => "list <map>"
    publish :variable => :postfix_mda, :type => "symbol"
    publish :variable => :fetchmail_mode, :type => "string"
    publish :variable => :fetchmail, :type => "list <map>"
    publish :variable => :virtual_users, :type => "list <map>"
    publish :variable => :smtp_auth, :type => "list <map>"
    publish :variable => :system_mail_sender, :type => "string"
    publish :variable => :protocol_choices, :type => "list <string>"
    publish :variable => :touched, :type => "boolean"
    publish :variable => :install_packages, :type => "list <string>"
    publish :variable => :remove_packages, :type => "list <string>"
    publish :variable => :cron_file, :type => "string"
    publish :variable => :check_interval, :type => "integer"
    publish :function => :Touch, :type => "void (boolean)"
    publish :function => :CreateConfig, :type => "boolean ()"
    publish :function => :ProbePackages, :type => "string ()"
    publish :function => :Read, :type => "boolean (block <boolean>)"
    publish :function => :ReadWithoutCallback, :type => "boolean ()"
    publish :function => :Fake, :type => "void ()"
    publish :function => :WriteGeneral, :type => "boolean ()"
    publish :function => :WriteMasquerading, :type => "boolean ()"
    publish :function => :WriteDownloading, :type => "boolean ()"
    publish :function => :WriteAliasesAndVirtual, :type => "boolean ()"
    publish :function => :WriteSmtpAuth, :type => "boolean ()"
    publish :function => :WriteFlush, :type => "boolean ()"
    publish :function => :WriteConfig, :type => "boolean ()"
    publish :function => :WriteServices, :type => "boolean ()"
    publish :function => :Write, :type => "boolean (block <boolean>)"
    publish :function => :WriteWithoutCallback, :type => "boolean ()"
    publish :function => :Import, :type => "boolean (map)"
    publish :function => :Export, :type => "map ()"
    publish :function => :Summary, :type => "string ()"
    publish :function => :AutoPackages, :type => "map ()"
  end

  Mail = MailClass.new
  Mail.main
end
