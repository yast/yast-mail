# encoding: utf-8

# File:
#   include/mail/ui.ycp
#
# Package:
#   Configuration of mail
#
# Summary:
#   User interface functions.
#
# Authors:
#   Martin Vidner <mvidner@suse.cz>
#
# $Id$
#
# All user interface functions.
#
module Yast
  module MailUiInclude
    def initialize_mail_ui(include_target)
      Yast.import "UI"

      textdomain "mail"

      Yast.import "Wizard"
      Yast.import "Progress"
      Yast.import "Mode"
      Yast.import "Mail"
      Yast.import "MailAliases"
      Yast.import "Hostname"
      Yast.import "CWMFirewallInterfaces"

      Yast.import "Popup"
      Yast.import "Label"
      Yast.import "Sequencer"
      Yast.import "Package"

      Yast.include include_target, "mail/helps.rb"
      Yast.include include_target, "mail/wj.rb"

      # A command line argument can override what is read from SCR.
      # Used when starting mail from lan/modem.
      @preselect_connection_type = nil

      @dialogs = {
        "read"             => [lambda { ReadDialog() }, true],
        "confirm"          => [lambda { ConfirmDialog() }, true],
        "write"            => [lambda { WriteDialog() }, true],
        "mta"              => lambda { MtaSelectionDialog() },
        "connection_type"  => lambda { ConnectionTypeDialog() },
        "outgoing"         => lambda { OutgoingDialog() },
        "incoming"         => lambda { IncomingDialog() },
        "outgoing-details" => lambda { OutgoingDetailsDialog() },
        "outgoing-auth"    => lambda { OutgoingAuthOptions() },
        "downloading"      => lambda { DownloadingDialog() },
        "aliases"          => lambda { AliasesDialog() },
        "virtual"          => lambda { VirtualDialog() },
        "common-next"      => [lambda { JustNext() }, true]
      }

      @common_sequence = {
        #"ws_start" : must be defined in an overriding sequence
        "connection_type"  => {
          :abort => :abort,
          :next  => "outgoing",
          :none  => "common-next"
        },
        "outgoing"         => {
          :abort              => :abort,
          :outgoing_details   => "outgoing-details",
          :outgoing_auth_opts => "outgoing-auth",
          :next               => "incoming"
        },
        "incoming"         => {
          :abort       => :abort,
          :downloading => "downloading",
          :aliases     => "aliases",
          :virtual     => "virtual",
          :next        => "common-next"
        },
        "outgoing-details" => { :abort => :abort, :next => "outgoing" },
        "outgoing-auth"    => { :abort => :abort, :next => "outgoing" },
        "downloading"      => { :abort => :abort, :next => "incoming" },
        "aliases"          => { :abort => :abort, :next => "incoming" },
        "virtual"          => { :abort => :abort, :next => "incoming" },
        "common-next"      => { :next => :next }
      }
    end

    # Read settings dialog
    # @return `abort or `next
    def ReadDialog
      Wizard.SetScreenShotName("mail-0-read")
      # Set help text
      Wizard.RestoreHelp(ReadDialogHelp())

      # A callback function for abort
      callback = lambda { UI.PollInput == :abort }

      # Read the configuration
      was_ok = true
      if Mode.screen_shot
        Mail.Fake
        # make it possible to snap this dialog
        Builtins.sleep(3000)
        UI.PollInput
      else
        was_ok = Mail.Read(callback)
      end

      # TODO FIXME possibly handle the abort
      if was_ok
        if !Mail.CreateConfig
          setting = "MAIL_CREATE_CONFIG"
          # Translators: continue/cancel dialog
          # %1 is a sysconfig variable name
          was_ok = Popup.ContinueCancel(
            Builtins.sformat(
              _(
                "The setting %1 is turned off. You have\n" +
                  "probably modified the configuration files directly.\n" +
                  "If you continue, it will be turned on and\n" +
                  "Config Postfix will overwrite manual changes.\n"
              ),
              setting
            )
          )
        end
      else
        if Mail.mta == :other
          # After text freeze, but
          # a) either something is very broken -> user must know
          # b) user installed a different MTA -> knowledgeable enough to
          # ba) never see this message anyway
          # bb) read English
          # TODO: look at exim and mention it in the popup
          # Translators: error popup
          Popup.Error(
            _(
              "YaST can only configure Postfix and Sendmail,\nbut neither of them is installed."
            )
          )
        end
      end
      Wizard.RestoreScreenShotName
      was_ok ? :next : :abort
    end

    # Confirmation dialog before saving and installing needed packages
    # @return `back or `next
    def ConfirmDialog
      # not to be displayed, #37554.
      # but ProbePackages still has to be called.

      # continue-cancel popup
      message1 = _("The configuration will be written now.\n")
      message2 = Mail.ProbePackages
      #    return Popup::ContinueCancel (message1 + message2) ? `next : `back;
      :next
    end

    # Write settings dialog
    # @return `abort or `next
    def WriteDialog
      if Mode.screen_shot
        Builtins.y2milestone("Screenshot mode - skipping Write")
        return :next
      end

      # Install packages if needed.
      # Cannot do it in Write, autoinstall does it differently.
      if Ops.greater_than(Builtins.size(Mail.install_packages), 0) ||
          Ops.greater_than(Builtins.size(Mail.remove_packages), 0)
        Package.DoInstallAndRemove(Mail.install_packages, Mail.remove_packages)
      end

      # Set help text
      Wizard.RestoreHelp(WriteDialogHelp())

      # A callback function for abort
      callback = lambda { UI.PollInput == :abort }

      # Read the configuration
      was_ok = Mail.Write(callback)

      # TODO FIXME possibly handle the abort

      was_ok ? :next : :abort
    end

    # MTA selection dialog
    # (only for autoinstallation, otherwise probed in Mail::Read)
    # @return `abort or `next
    def MtaSelectionDialog
      Wizard.SetScreenShotName("mail-0-mta")

      mta = Mail.mta
      # for now. TODO: disable Next if none selected
      mta = :postfix if mta != :sendmail && mta != :postfix

      # Translators: dialog caption
      # Mailer: Sendmail or Postfix
      caption = _("Mail transfer agent")
      contents = Frame(
        # Translators: frame label
        # Mailer: Sendmail or Postfix
        _("Mail transfer agent"),
        RadioButtonGroup(
          Id(:mtag),
          HSquash(
            VBox(
              HSpacing(23), # qt bug workaround, #23979
              VSpacing(0.2),
              # MTA name does not need translation
              Left(
                RadioButton(
                  Id(:sendmail),
                  Opt(:autoShortcut),
                  "Sendmail",
                  mta == :sendmail
                )
              ),
              # MTA name does not need translation
              Left(
                RadioButton(
                  Id(:postfix),
                  Opt(:autoShortcut),
                  "Postfix",
                  mta == :postfix
                )
              ),
              VSpacing(0.2)
            )
          )
        )
      )

      Wizard.SetContentsButtons(
        caption,
        contents,
        MtaSelectionDialogHelp(),
        Label.BackButton,
        Label.NextButton
      )

      ret = nil
      while true
        ret = UI.UserInput
        ret = :abort if ret == :cancel

        if ret == :back || ret == :next ||
            ret == :abort && Popup.ReallyAbort(Mail.touched)
          break
        end
      end

      if ret == :next
        mta = Convert.to_symbol(UI.QueryWidget(Id(:mtag), :CurrentButton))
        Mail.Touch(Mail.mta != mta)
        Mail.mta = mta
      end
      Wizard.RestoreScreenShotName
      Convert.to_symbol(ret)
    end

    # D1
    # @return `back, `abort, `next or `none
    def ConnectionTypeDialog
      Wizard.SetScreenShotName("mail-1-conntype")

      widgets = []

      ct = Mail.connection_type
      ama = Mail.use_amavis
      ct = @preselect_connection_type if @preselect_connection_type != nil

      # Translators: dialog caption
      caption = _("General Settings")
      contents = Frame(
        # Translators: frame label
        _("Connection type"),
        RadioButtonVBox(
          :ctg,
          [
            # Translators: radio button label
            RadioButton(
              Id(:permanent),
              Opt(:notify),
              _("&Permanent"),
              ct == :permanent
            ),
            # Translators: radio button label
            RadioButton(Id(:dialup), Opt(:notify), _("&Dial-up"), ct == :dialup),
            # Translators: radio button label
            RadioButton(
              Id(:none),
              Opt(:notify),
              _("No &connection"),
              ct == :none
            ),
            # Translators: radio button label
            RadioButton(
              Id(:nodaemon),
              Opt(:notify),
              _("Do not start Postfix as Daemon"),
              ct == :nodaemon
            )
          ]
        )
      )

      amavis_t = Left(WJ_MakeWidget(:use_amavis))
      widgets = Builtins.add(widgets, :use_amavis)
      dkim_t = Left(WJ_MakeWidget(:use_dkim))
      widgets = Builtins.add(widgets, :use_dkim)

      contents = HSquash(VBox(contents, VSpacing(1), amavis_t, dkim_t))

      Wizard.SetContentsButtons(
        caption,
        contents,
        WJ_MakeHelp(Builtins.prepend(widgets, ConnectionTypeDialogHelp())),
        Label.BackButton,
        Label.NextButton
      )
      ret = nil
      while true
        ct = Convert.to_symbol(UI.QueryWidget(Id(:ctg), :CurrentButton))
        if ct == :permanent || ct == :dialup
          UI.ChangeWidget(Id(:use_amavis), :Enabled, true)
          UI.ChangeWidget(Id(:use_dkim), :Enabled, true)
          Wizard.RestoreNextButton
        elsif ct == :nodaemon
          UI.ChangeWidget(Id(:use_amavis), :Value, false)
          UI.ChangeWidget(Id(:use_amavis), :Enabled, false)
          UI.ChangeWidget(Id(:use_dkim), :Value, false)
          UI.ChangeWidget(Id(:use_dkim), :Enabled, false)
        elsif ct == :none
          UI.ChangeWidget(Id(:use_amavis), :Value, false)
          UI.ChangeWidget(Id(:use_amavis), :Enabled, false)
          UI.ChangeWidget(Id(:use_dkim), :Value, false)
          UI.ChangeWidget(Id(:use_dkim), :Enabled, false)
          Wizard.SetNextButton(:next, Label.FinishButton)
        end
        ama = Convert.to_boolean(UI.QueryWidget(Id(:use_amavis), :Value))
        if ama
          UI.ChangeWidget(Id(:use_dkim), :Enabled, true)
        else
          UI.ChangeWidget(Id(:use_dkim), :Value, false)
          UI.ChangeWidget(Id(:use_dkim), :Enabled, false)
        end

        ret = UI.UserInput
        ret = :abort if ret == :cancel

        if ret == :back || ret == :abort && Popup.ReallyAbort(Mail.touched)
          break
        elsif ret == :next
          break if WJ_Validate(widgets)
        end
      end

      if ret == :next
        WJ_Set(widgets)

        ct = Convert.to_symbol(UI.QueryWidget(Id(:ctg), :CurrentButton))
        Mail.Touch(Mail.connection_type != ct)
        Mail.connection_type = ct

        ret = ct == :none ? :none : ret
      end
      # avoid overriding the choice the user has made
      @preselect_connection_type = nil
      Wizard.RestoreScreenShotName
      Convert.to_symbol(ret)
    end

    # D2
    # @return `back, `abort, `next or `outgoing_details
    def OutgoingDialog
      Wizard.SetScreenShotName("mail-21-outgoing")

      _TLSnone = Mail.smtp_use_TLS == "no"
      _TLSuse = Mail.smtp_use_TLS == "yes"
      _TLSmust = Mail.smtp_use_TLS == "must"

      # what buttons can be used to leave this dialog
      #(except the std wizarding ones)
      buttons = []
      widgets = [:outgoing_mail_server]

      # Translators: dialog caption
      caption = _("Outgoing Mail")

      o_contents = VSquash(
        VBox(
          WJ_MakeWidget(:outgoing_mail_server),
          # TLS
          Label(_("TLS encryption")),
          RadioButtonGroup(
            Id(:TLS),
            HBox(
              Left(RadioButton(Id("no"), _("No"), _TLSnone)),
              Left(RadioButton(Id("yes"), _("Use"), _TLSuse)),
              Left(RadioButton(Id("must"), _("Enforce"), _TLSmust))
            )
          ),
          HBox(
            PushButton(Id(:outgoing_details), _("&Masquerading")),
            PushButton(Id(:outgoing_auth_opts), _("&Authentication"))
          )
        )
      )
      buttons = Builtins.add(buttons, :outgoing_details)
      buttons = Builtins.add(buttons, :outgoing_auth_opts)

      # frame label
      o_frame = Frame(_("Outgoing Mail"), o_contents)
      contents = HSquash(VBox(VStretch(), o_frame, VStretch()))

      help = "" #TODO
      Wizard.SetContentsButtons(
        caption,
        contents,
        WJ_MakeHelp(widgets),
        Label.BackButton,
        Label.NextButton
      )

      ret = nil
      while true
        ret = Convert.to_symbol(UI.UserInput)
        ret = :abort if ret == :cancel

        if ret == :back || ret == :abort && Popup.ReallyAbort(Mail.touched)
          break
        elsif ret == :next || Builtins.contains(buttons, ret)
          # input validation
          # For consistency, all querywidgets are done here

          if WJ_Validate(widgets)
            # all checks OK, break the input loop
            break
          end
        end
      end

      if ret == :next || Builtins.contains(buttons, ret)
        Mail.smtp_use_TLS = Convert.to_string(UI.QueryWidget(Id(:TLS), :Value))
        WJ_Set(widgets)
      end
      Wizard.RestoreScreenShotName
      ret
    end

    # D2
    # @return `back, `abort, `next or `outgoing_details
    def IncomingDialog
      Wizard.SetScreenShotName("mail-22-incoming")

      buttons = []
      # watch out, fm_widgets are not part of widgets
      # because of special validation requirements
      widgets = [:listen_remote]
      # firewall widget using CWM
      fw_settings = {
        "services"        => ["service:smtp"],
        "display_details" => true
      }
      fw_cwm_widget = CWMFirewallInterfaces.CreateOpenFirewallWidget(
        fw_settings
      )

      # Translators: dialog caption
      caption = _("Incoming Mail")

      i_contents = VBox()

      i_contents = Builtins.add(i_contents, Left(WJ_MakeWidget(:listen_remote)))
      i_contents = Builtins.add(
        i_contents,
        Ops.get_term(fw_cwm_widget, "custom_widget", Empty())
      )

      fm_widgets = []
      if true # always embed the first account
        # Edit the first fetchmail item here.
        # Copy it into the edit buffer.
        @fetchmail_item = Ops.get(Mail.fetchmail, 0, {})

        fm_widgets = [
          :fm_server,
          :fm_protocol,
          :fm_remote_user,
          :fm_password,
          :fm_local_user
        ]

        fm_contents = VBox(
          HSpacing(40), # prevent fm_password being squashed in curses
          HBox(
            WJ_MakeWidget(:fm_server),
            HSpacing(1),
            WJ_MakeWidget(:fm_protocol)
          ),
          HBox(
            WJ_MakeWidget(:fm_remote_user),
            HSpacing(1),
            WJ_MakeWidget(:fm_password)
          ),
          HBox(
            Bottom(WJ_MakeWidget(:fm_local_user)),
            HSpacing(1),
            # pushbutton
            Bottom(PushButton(Id(:downloading), Opt(:key_F7), _("&Details...")))
          ),
          HBox(
            Left(
              ComboBox(
                Id(:fm_start),
                _("Start &fetchmail"),
                ["manual", "daemon"]
              )
            )
          )
        )
        # frame label: mail downloading (fetchmail)
        fm_frame = Frame(_("&Downloading"), fm_contents)
        i_contents = Builtins.add(
          i_contents,
          HBox(HSpacing(1), fm_frame, HSpacing(1))
        )
      end

      i_contents = Builtins.add(i_contents, WJ_MakeWidget(:root_alias))
      widgets = Builtins.add(widgets, :root_alias)

      if Mail.mta == :postfix
        i_contents = Builtins.add(i_contents, WJ_MakeWidget(:delivery_mode))
        widgets = Builtins.add(widgets, :delivery_mode)
      end

      i_contents = Builtins.add(
        i_contents,
        # menu button: details of incoming mail
        HBox(
          PushButton(Id(:aliases), _("&Aliases...")),
          PushButton(Id(:virtual), _("&Virtual domains..."))
        )
      )
      buttons = Builtins.flatten([buttons, [:downloading, :aliases, :virtual]])

      # frame label
      #    term i_frame = `Frame (_("Incoming Mail"), i_contents);
      contents = HSquash(VBox(VStretch(), i_contents, VStretch()))

      help = "" #TODO
      Wizard.SetContentsButtons(
        caption,
        contents,
        Ops.add(WJ_MakeHelp(widgets), Ops.get_string(fw_cwm_widget, "help", "")),
        Label.BackButton,
        Label.FinishButton
      )

      # set combo boxes to proper values
      WJ_GetWidget(:fm_protocol)
      WJ_GetWidget(:fm_local_user)
      WJ_GetWidget(:delivery_mode)
      # initialize the widget (set the current value)
      CWMFirewallInterfaces.OpenFirewallInit(fw_cwm_widget, "")
      UI.ChangeWidget(Id(:fm_start), :Value, Mail.fetchmail_mode)

      # nothing entered in the dowloading items - don't save them
      fm_empty = true

      event = nil
      ret = nil
      while true
        event = UI.WaitForEvent
        ret = Ops.get(event, "ID")
        ret = :abort if ret == :cancel
        # handle the events, enable/disable the button, show the popup if button clicked
        CWMFirewallInterfaces.OpenFirewallHandle(fw_cwm_widget, "", event)

        if ret == :back || ret == :abort && Popup.ReallyAbort(Mail.touched)
          break
        elsif ret == :next || Builtins.contains(buttons, ret)
          Mail.fetchmail_mode = Convert.to_string(
            UI.QueryWidget(Id(:fm_start), :Value)
          )
          # input validation
          # For consistency, all querywidgets are done here
          if WJ_Validate(widgets)
            fm_empty = UI.QueryWidget(Id(:fm_server), :Value) == "" &&
              UI.QueryWidget(Id(:fm_remote_user), :Value) == "" &&
              UI.QueryWidget(Id(:fm_password), :Value) == "" &&
              UI.QueryWidget(Id(:fm_local_user), :Value) == ""
            if fm_empty || WJ_Validate(fm_widgets)
              # all checks OK, break the input loop
              break
            end
          end
        end
      end

      if ret == :next || Builtins.contains(buttons, ret)
        WJ_Set(widgets)
        # grab current settings, store them to SuSEFirewall::
        CWMFirewallInterfaces.OpenFirewallStore(fw_cwm_widget, "", event)

        if !fm_empty
          WJ_Set(fm_widgets)
          # CHECK: aliasing is not harmful here
          Ops.set(Mail.fetchmail, 0, @fetchmail_item)

          # -------------- fix of bug #29919:
          # -------------- propose local domains when fetchmail is used:
          if Mail.fetchmail != [] && Mail.local_domains == [] &&
              Mail.mta == :postfix
            ld = ["\\$myhostname", "localhost.\\$mydomain", "\\$mydomain"]
            # popup text
            # %1: variable name (eg. POSTFIX_LOCALDOMAINS)
            # %2: file name (eg. /etc/sysconfig/postfix)
            # %3: value (about 50 characters)
            if Popup.YesNo(
                Builtins.sformat(
                  _(
                    "To be able to deliver mail to your local MTA,\n" +
                      "the value of %1 in %2 will be set to\n" +
                      "\"%3\"."
                  ),
                  "POSTFIX_LOCALDOMAINS",
                  "/etc/sysconfig/postfix",
                  Builtins.mergestring(ld, ", ")
                )
              )
              Mail.local_domains = deep_copy(ld)
            end
          end
        end
      end
      Wizard.RestoreScreenShotName
      Convert.to_symbol(ret)
    end

    # (taken from y2c_users ui.ycp)
    # @param [String] username a string
    # @return Whether a string contains only valid user name characters
    def check_username(username)
      #DUH, auth_dialogs.ycp, users.ycp and Users.ycp have conflicing definitions!
      valid_logname_chars = "0123456789abcdefghijklmnopqrstuvwxyz-_"

      firstchar = Builtins.substring(username, 0, 1)
      username != "" &&
        (Ops.greater_or_equal(firstchar, "a") &&
          Ops.less_or_equal(firstchar, "z") ||
          firstchar == "_") &&
        Builtins.findfirstnotof(username, valid_logname_chars) == nil
    end

    # (taken from y2c_users ui.ycp)
    # @return Describe a valid username
    def valid_username
      # There is a check whether the information from the UI is
      # correct and complete.  The login name may contain only
      # certain characters and must begin with a letter.
      # Already in Translation Memory
      _(
        "The user login may contain only\n" +
          "lower case letters, digits, \"-\" and \"_\"\n" +
          "and must begin with a letter or \"_\".\n" +
          "Please try again.\n"
      )
    end

    # See RFC 2822, 3.4
    # But for now, no-spaces@valid_domainname
    # @param [String] address an address to check
    # @return valid?
    def check_mail_address(address)
      parts = Builtins.splitstring(address, "@")
      return false if Builtins.size(parts) != 2

      check_mail_local_part(Ops.get(parts, 0, "")) &&
        Hostname.CheckDomain(Ops.get(parts, 1, ""))
    end

    # D2.1.1
    # Used for adding and editing a user masquerading entry.
    # @param [Hash] defaultv	$["user": "address":] or just $[]
    # @param [Array<Hash>] existing	current masqueading list
    # @return		$["comment": "", "user": "address":] or $[] on cancel
    def MasqueradeUserPopup(defaultv, existing)
      defaultv = deep_copy(defaultv)
      existing = deep_copy(existing)
      user = Ops.get_string(defaultv, "user", "")
      address = Ops.get_string(defaultv, "address", "")
      forbidden = Builtins.maplist(existing) do |e|
        Ops.get_string(e, "user", "")
      end

      contents = HBox(
        HSpacing(1),
        VBox(
          VSpacing(0.2),
          # Translators: popup dialog heading
          Heading(_("Sender address rewriting")),
          Mode.config ?
            # Translators: text entry label
            Left(TextEntry(Id(:user), _("&Local user"), user)) :
            Left(
              ComboBox(
                Id(:user),
                Opt(:editable, :hstretch),
                _("&Local user"),
                GetLocalUsers()
              )
            ),
          # Translators: text entry label
          Left(TextEntry(Id(:address), _("&Display as"), address)),
          VSpacing(0.2),
          ButtonBox(
            PushButton(Id(:ok), Opt(:default, :key_F10), Label.OKButton),
            PushButton(Id(:cancel), Opt(:key_F9), Label.CancelButton)
          ),
          VSpacing(0.2)
        ),
        HSpacing(1)
      )

      UI.OpenDialog(Opt(:decorated), contents)
      UI.ChangeWidget(Id(:user), :Value, user)
      UI.SetFocus(Id(:user))

      ret = nil
      while true
        ret = UI.UserInput
        if ret == :cancel
          break
        elsif ret == :ok
          # Input validation
          user = Convert.to_string(UI.QueryWidget(Id(:user), :Value))
          address = Convert.to_string(UI.QueryWidget(Id(:address), :Value))


          if !check_username(user)
            UI.SetFocus(Id(:user))
            Popup.Error(valid_username)
          elsif Builtins.contains(forbidden, user)
            UI.SetFocus(Id(:user))
            # Translators: error message
            Popup.Error(_("The address for this user is already defined."))
          elsif !check_mail_address(address)
            # string valid_mail_address
            # no-spaces@valid_domainname
            UI.SetFocus(Id(:address))
            # error popup
            Popup.Error(_("The mail address format is incorrect."))
          else
            # all checks OK, break the input loop
            break
          end
        end
      end

      UI.CloseDialog

      ret == :ok ?
        { "comment" => "", "user" => user, "address" => address } :
        {}
    end

    # D2.1
    # @return `back, `abort or `next
    def OutgoingDetailsDialog
      Wizard.SetScreenShotName("mail-2o-outgoing-details")

      mod = listToString(Mail.masquerade_other_domains)
      lmod = []
      mu = deep_copy(Mail.masquerade_users)

      # Translators: dialog caption
      caption = _("Masquerading")
      contents = VBox(
        VSpacing(0.2),
        RadioButtonGroup(
          Id(:mdg),
          VBox(
            VSpacing(0.2),
            WJ_MakeWidget(:from_header),
            VSpacing(0.2),
            WJ_MakeWidget(:local_domains),
            VSpacing(0.2),
            Left(
              RadioButton(
                Id(:masqlocal),
                # Translators: radio button label
                _("Masquerade &local domains"),
                mod == ""
              )
            ),
            #		    `HBox (
            #			`HSpacing (2),
            #			`TextEntry (`id (`masqdomains), `opt (`disabled), _("That is"), ld)
            #//			`Left (`Label (`opt (`outputField, `hstretch), ld))
            #			),
            # Translators: radio button label
            Left(
              RadioButton(
                Id(:masqothers),
                _("Ma&squerade other domains"),
                mod != ""
              )
            ),
            HBox(
              HSpacing(2),
              # Translators: text entry label
              TextEntry(
                Id(:masqdomains),
                Opt(:notify),
                _("Do&mains to masquerade"),
                mod
              )
            )
          )
        ),
        VSpacing(1),
        Table(
          Id(:tab),
          Opt(:notify, :immediate),
          # Translators: table column headings
          Header(
            _("Local user"),
            # Translators: table column headings
            _("Display as")
          ),
          makeItems(mu, ["user", "address"])
        ),
        # 	    `HBox (
        # 		`HWeight (1, `ComboBox (`id (`user), `opt (`editable), _("Local user"),
        # 					["holly", "jane", "tarzan"])),
        # 		`HWeight (2, `TextEntry (`id (`address), _("Display as"), "holly@red.dwarf"))
        # 		),
        HBox(
          PushButton(Id(:add), Opt(:key_F3), _("A&dd")),
          PushButton(Id(:edit), Opt(:key_F4), _("&Edit")),
          PushButton(Id(:delete), Opt(:key_F5), _("Dele&te"))
        ),
        VSpacing(1)
      )

      help = Ops.add(
        WJ_MakeHelp([:from_header, :local_domains]),
        MasqueradingDialogHelp()
      )

      Wizard.SetContentsButtons(
        caption,
        contents,
        help,
        Label.BackButton,
        Label.OKButton
      )

      ret = nil
      @edit_touched = false
      while true
        any_items = UI.QueryWidget(Id(:tab), :CurrentItem) != nil
        UI.ChangeWidget(Id(:edit), :Enabled, any_items)
        UI.ChangeWidget(Id(:delete), :Enabled, any_items)

        # Kludge, because a `Table still does not have a shortcut.
        # watch out, a textentry sends UI too
        UI.SetFocus(Id(:tab)) if ret != :masqdomains

        ret = Convert.to_symbol(UI.UserInput)
        ret = :abort if ret == :cancel

        if ret == :masqdomains
          UI.ChangeWidget(Id(:mdg), :CurrentButton, :masqothers)
        elsif Builtins.contains([:add, :edit, :delete], ret)
          mu = EditTable(
            ret,
            mu,
            ["user", "address"],
            fun_ref(method(:MasqueradeUserPopup), "map (map, list <map>)"),
            :tab
          )
        elsif ret == :abort && Popup.ReallyAbort(Mail.touched || @edit_touched) ||
            ret == :back
          break
        elsif ret == :next
          # Input validation
          # For consistency, all querywidgets are done here.
          # The table contents is maintained and validated
          # at the EditTable call.

          rb = Convert.to_symbol(UI.QueryWidget(Id(:mdg), :CurrentButton))
          if rb == :masqothers
            mod = Convert.to_string(UI.QueryWidget(Id(:masqdomains), :Value))
            lmod = stringToList(mod)
          else
            lmod = []
          end

          if !Validate_from_header(:from_header)
            Builtins.y2debug("nothing")
          elsif !Validate_local_domains(:local_domains)
            Builtins.y2debug("nothing, already done")
          elsif Builtins.find(lmod) { |s| !Hostname.CheckDomain(s) } != nil
            UI.SetFocus(Id(:masqdomains))
            # Translators: error popup
            # Already in Translation Memory
            msg = _("The domain name is incorrect")
            # TODO: describe a valid domain name
            Popup.Error(msg)
          else
            # all checks OK, break the input loop
            break
          end
        end
      end

      if ret == :next
        # all querywidgets are already done by the validation part
        Set_from_header(:from_header)
        Set_local_domains(:local_domains)

        Mail.Touch(Mail.masquerade_other_domains != lmod)
        Mail.masquerade_other_domains = deep_copy(lmod)

        Mail.Touch(Mail.masquerade_users != mu)
        Mail.masquerade_users = deep_copy(mu)
      end
      Wizard.RestoreScreenShotName
      ret
    end

    # D2.2
    # Outgoing server authentification
    # @return `back, `abort or `next
    def OutgoingAuthOptions
      Wizard.SetScreenShotName("mail-2o-outgoing-authentication")

      #string mod = listToString (Mail::masquerade_other_domains);
      #list<string> lmod = [];
      #list<map> mu = Mail::masquerade_users;

      # Translators: dialog caption
      caption = _("Outgoing Server Authentication")
      contents = VBox(
        HBox(
          HWeight(1, Empty()),
          HWeight(
            3,
            VBox(
              # text entry
              TextEntry(Id(:server), _("Outgoing &Server")),
              # text entry
              TextEntry(Id(:user), _("&User name")),
              # password entry
              Password(Id(:passw), _("&Password"))
            )
          ),
          HWeight(1, Empty())
        )
      )
      #);

      Wizard.SetContentsButtons(
        caption,
        contents,
        AuthenticationDialogHelp(),
        Label.BackButton,
        Label.OKButton
      )

      ret = nil
      config = Ops.get(Mail.smtp_auth, 0, {})

      if config == {}
        config = Builtins.add(config, "server", Mail.outgoing_mail_server)
        config = Builtins.add(config, "user", "")
        config = Builtins.add(config, "password", "")
      end

      UI.ChangeWidget(Id(:server), :Value, Ops.get_string(config, "server", ""))
      UI.ChangeWidget(Id(:user), :Value, Ops.get_string(config, "user", ""))
      UI.ChangeWidget(
        Id(:passw),
        :Value,
        Ops.get_string(config, "password", "")
      )

      while true
        ret = UI.UserInput
        ret = :abort if ret == :cancel

        if ret == :abort && Popup.ReallyAbort(Mail.touched) || ret == :back
          break
        elsif ret == :next
          server = Convert.to_string(UI.QueryWidget(Id(:server), :Value))
          user = Convert.to_string(UI.QueryWidget(Id(:user), :Value))
          password = Convert.to_string(UI.QueryWidget(Id(:passw), :Value))

          if server == "" && user == "" && password == ""
            # wants to delete it, ok
            config = {}
            break
          else
            Ops.set(config, "server", server)
            Ops.set(config, "user", user)
            Ops.set(config, "password", password)
          end

          # validity checks: reuse fetchmail widgets
          if Validate_outgoing_mail_server(:server) &&
              Validate_fm_remote_user(:user)
            break
          end
        end
      end

      if ret == :next
        # all querywidgets are already done by the validation part
        Mail.Touch(Ops.get(Mail.smtp_auth, 0, {}) != config)
        Ops.set(Mail.smtp_auth, 0, config)
        # removing? had to add it first so that there is something to remove.
        if config == {}
          Mail.smtp_auth = Builtins.remove(Mail.smtp_auth, 0)
        else
          # #158220
          Mail.Touch(
            Mail.outgoing_mail_server != Ops.get_string(config, "server", "")
          )
          Mail.outgoing_mail_server = Ops.get_string(config, "server", "")
        end
      end
      Wizard.RestoreScreenShotName
      Convert.to_symbol(ret)
    end

    # D3.1
    # @param [Hash] defaultv $[server:, protocol:, remote_user:, local_user:, password:, ...]
    # @param [Array<Hash>] existing	unused
    # @return edited data (with no other fields) or $[] on cancel
    def FetchmailPopup(defaultv, existing)
      defaultv = deep_copy(defaultv)
      existing = deep_copy(existing)
      @fetchmail_item = deep_copy(defaultv)
      @fetchmail_item_touched = false

      widgets = [
        :fm_server,
        :fm_protocol,
        :fm_remote_user,
        :fm_password,
        :fm_local_user
      ]

      contents = HBox(
        HSpacing(1),
        VBox(
          VSpacing(0.2),
          # Translators: popup dialog heading
          Heading(_("Mail downloading")),
          Left(WJ_MakeWidget(:fm_server)),
          Left(WJ_MakeWidget(:fm_protocol)),
          Left(WJ_MakeWidget(:fm_remote_user)),
          Left(WJ_MakeWidget(:fm_password)),
          Left(WJ_MakeWidget(:fm_local_user)),
          VSpacing(0.2),
          ButtonBox(
            PushButton(Id(:ok), Opt(:default, :key_F10), Label.OKButton),
            PushButton(Id(:cancel), Opt(:key_F9), Label.CancelButton)
          ),
          VSpacing(0.2)
        ),
        HSpacing(1)
      )

      UI.OpenDialog(Opt(:decorated), contents)
      # set combo boxes to proper values
      WJ_GetWidget(:fm_protocol)
      WJ_GetWidget(:fm_local_user)
      UI.SetFocus(Id(:fm_server))

      ret = nil
      while true
        ret = UI.UserInput
        if ret == :cancel
          break
        elsif ret == :ok
          # Input validation
          if WJ_Validate(widgets)
            # all checks OK, break the input loop
            break
          end
        end
      end

      WJ_Set(widgets) # TODO hope it is ok to mess it up
      UI.CloseDialog

      ret == :ok ? @fetchmail_item : {}
    end


    # D3
    # @return `back, `abort or `next
    def DownloadingDialog
      Wizard.SetScreenShotName("mail-2ia-download")
      #List of maps: $[server:, protocol:, remote_user:, local_user:, password:]
      fm = deep_copy(Mail.fetchmail)

      # Translators: dialog caption
      caption = _("Mail downloading")
      contents = VBox(
        VSpacing(0.2),
        #  * no time to implement this :-(
        #  * #22903
        # `Frame (
        # 		// Translators: frame label
        # 		// When should Fetchmail run
        # 		// Fetchmail is a program name, do not translate
        # 		_("Run Fetchmail"),
        # 		RadioButtonVBox (
        # 		    `run_fm_g,
        # 		    [
        # 			// Translators: radio button label
        # 			`RadioButton (`id (`run_fm_man), _("&Manually"), true), // TODO fake
        # 			// Translators: radio button label
        # 			`RadioButton (`id (`run_fm_ppp), _("For &dial-up network connections"), false),
        # 			// Translators: radio button label
        # 			`RadioButton (`id (`run_fm_net), _("For &all network connections"), false),
        # 			]
        # 		    )
        # 		),
        # `VSpacing (0.5),
        Table(
          Id(:tab),
          Opt(:notify, :immediate),
          # Translators: table column headings
          Header(
            _("Server"),
            # Translators: table column headings
            _("Protocol"),
            # Translators: table column headings
            _("User"),
            # Translators: table column headings
            _("Local user")
          ),
          makeItems(fm, ["server", "protocol", "remote_user", "local_user"])
        ),
        HBox(
          PushButton(Id(:add), Opt(:key_F3), _("A&dd")),
          PushButton(Id(:edit), Opt(:key_F4), _("&Edit")),
          PushButton(Id(:delete), Opt(:key_F5), _("De&lete"))
        ),
        VSpacing(0.2)
      )

      Wizard.SetContentsButtons(
        caption,
        contents,
        DownloadingDialogHelp(),
        Label.BackButton,
        Label.OKButton
      )

      UI.ChangeWidget(Id(:edit), :Enabled, false)
      UI.ChangeWidget(Id(:delete), :Enabled, false)

      ret = nil
      @edit_touched = false
      while true
        any_items = UI.QueryWidget(Id(:tab), :CurrentItem) != nil
        UI.ChangeWidget(Id(:edit), :Enabled, any_items)
        UI.ChangeWidget(Id(:delete), :Enabled, any_items)

        # Kludge, because a `Table still does not have a shortcut.
        UI.SetFocus(Id(:tab))

        ret = Convert.to_symbol(UI.UserInput)
        ret = :abort if ret == :cancel


        if Builtins.contains([:add, :edit, :delete], ret)
          fm = EditTable(
            ret,
            fm,
            ["server", "protocol", "remote_user", "local_user"],
            fun_ref(method(:FetchmailPopup), "map (map, list <map>)"),
            :tab
          )
        elsif ret == :abort && Popup.ReallyAbort(Mail.touched || @edit_touched) ||
            ret == :next ||
            ret == :back
          break
        end
      end

      if ret == :next
        Mail.Touch(Mail.fetchmail != fm)
        Mail.fetchmail = deep_copy(fm)
      end
      Wizard.RestoreScreenShotName
      ret
    end

    # D1.1.1, 1.2.1
    # Used for adding and editing an alias/virtual domain entry.
    # @param [Hash] defaultv	$["alias": "destinations": ?comment] or just $[]
    # @param [Array<Hash>] existing	current entry list
    # @return		$["comment": ""?, "alias": "destinations":] or $[] on cancel
    def AliasPopup(defaultv, existing)
      defaultv = deep_copy(defaultv)
      existing = deep_copy(existing)
      _alias = Ops.get_string(defaultv, "alias", "")
      destinations = Ops.get_string(defaultv, "destinations", "")
      forbidden = Builtins.maplist(existing) do |e|
        Ops.get_string(e, "alias", "")
      end

      contents = HBox(
        HSpacing(1),
        VBox(
          VSpacing(0.2),
          # Translators: popup dialog heading
          Heading(_("Incoming mail redirection")),
          # Translators: text entry label
          Left(TextEntry(Id(:alias), _("&Alias"), _alias)),
          # Translators: text entry label
          Left(TextEntry(Id(:destinations), _("&Destinations"), destinations)),
          VSpacing(0.2),
          ButtonBox(
            PushButton(Id(:ok), Opt(:default, :key_F10), Label.OKButton),
            PushButton(Id(:cancel), Opt(:key_F9), Label.CancelButton)
          ),
          VSpacing(0.2)
        ),
        HSpacing(1)
      )

      UI.OpenDialog(Opt(:decorated), contents)
      UI.SetFocus(Id(:alias))

      ret = nil
      while true
        ret = UI.UserInput
        if ret == :cancel
          break
        elsif ret == :ok
          # Input validation
          _alias = Convert.to_string(UI.QueryWidget(Id(:alias), :Value))
          destinations = Convert.to_string(
            UI.QueryWidget(Id(:destinations), :Value)
          )

          # TODO: this only works because check_mail_local part is too
          # permissive. Virtusertable aliases may contain @ so it is not
          # a local part and the check will need to be improved.
          # (But a postfix-style virtual domain will have an @-less entry.)
          if !check_mail_local_part(_alias)
            UI.SetFocus(Id(:alias))
            # Translators: error message
            Popup.Message(_("The alias format is incorrect."))
          elsif Builtins.contains(forbidden, _alias)
            UI.SetFocus(Id(:alias))
            # Translators: error message
            Popup.Message(
              _("The destinations for this alias are already defined.")
            )
          else
            # all checks OK, break the input loop
            break
          end
        end
      end

      UI.CloseDialog

      ret == :ok ?
        { "comment" => "", "alias" => _alias, "destinations" => destinations } :
        {}
    end


    # D1.1
    # @return `back, `abort or `next
    def AliasesDialog
      Wizard.SetScreenShotName("mail-2ib-aliases")
      aliases = MailAliases.MergeRootAlias(MailAliases.aliases)

      # Translators: dialog caption
      caption = _("Aliases")
      contents = VBox(
        VSpacing(0.2),
        Table(
          Id(:tab),
          Opt(:notify, :immediate),
          # Translators: table column headings
          Header(
            _("Alias"),
            # Translators: table column headings
            _("Destinations")
          ),
          makeItems(aliases, ["alias", "destinations"])
        ),
        Left(
          HBox(
            PushButton(Id(:add), Opt(:key_F3), _("A&dd")),
            PushButton(Id(:edit), Opt(:key_F4), _("&Edit")),
            PushButton(Id(:delete), Opt(:key_F5), _("De&lete"))
          )
        ),
        VSpacing(0.2)
      )

      Wizard.SetContentsButtons(
        caption,
        contents,
        AliasesDialogHelp(),
        Label.BackButton,
        Label.OKButton
      )

      ret = nil
      @edit_touched = false
      while true
        any_items = UI.QueryWidget(Id(:tab), :CurrentItem) != nil
        UI.ChangeWidget(Id(:edit), :Enabled, any_items)
        UI.ChangeWidget(Id(:delete), :Enabled, any_items)

        # Kludge, because a `Table still does not have a shortcut.
        UI.SetFocus(Id(:tab))

        ret = UI.UserInput

        ret_sym = nil
        ret_sym = Convert.to_symbol(ret) if Ops.is_symbol?(ret)

        ret = :abort if ret == :cancel

        if Builtins.contains([:add, :edit, :delete], ret_sym)
          aliases = EditTable(
            Convert.to_symbol(ret),
            aliases,
            ["alias", "destinations"],
            fun_ref(method(:AliasPopup), "map (map, list <map>)"),
            :tab
          )
        elsif ret == "man_aliases"
          Builtins.y2milestone("TODO: man aliases")
        elsif ret == :abort && Popup.ReallyAbort(Mail.touched || @edit_touched) ||
            ret == :next ||
            ret == :back
          break
        end
      end

      if ret == :next
        Mail.Touch(@edit_touched)
        MailAliases.aliases = deep_copy(aliases)
        MailAliases.FilterRootAlias
      end
      Wizard.RestoreScreenShotName
      Convert.to_symbol(ret)
    end


    # D1.2
    # @return `back, `abort or `next
    def VirtualDialog
      Wizard.SetScreenShotName("mail-2ic-virtdomains")
      vu = deep_copy(Mail.virtual_users)

      # Translators: dialog caption
      caption = _("Virtual domains")
      contents = VBox(
        VSpacing(0.2),
        Table(
          Id(:tab),
          Opt(:notify, :immediate),
          # Translators: table column headings
          Header(
            _("Alias"),
            # Translators: table column headings
            _("Destinations")
          ),
          makeItems(vu, ["alias", "destinations"])
        ),
        Left(
          HBox(
            PushButton(Id(:add), Opt(:key_F3), _("A&dd")),
            PushButton(Id(:edit), Opt(:key_F4), _("&Edit")),
            PushButton(Id(:delete), Opt(:key_F5), _("De&lete"))
          )
        ),
        VSpacing(0.2)
      )

      Wizard.SetContentsButtons(
        caption,
        contents,
        VirtualDialogHelp(),
        Label.BackButton,
        Label.OKButton
      )

      UI.ChangeWidget(Id(:edit), :Enabled, false)
      UI.ChangeWidget(Id(:delete), :Enabled, false)

      ret = nil
      @edit_touched = false
      while true
        any_items = UI.QueryWidget(Id(:tab), :CurrentItem) != nil
        UI.ChangeWidget(Id(:edit), :Enabled, any_items)
        UI.ChangeWidget(Id(:delete), :Enabled, any_items)

        # Kludge, because a `Table still does not have a shortcut.
        UI.SetFocus(Id(:tab))

        ret = Convert.to_symbol(UI.UserInput)
        ret = :abort if ret == :cancel


        if Builtins.contains([:add, :edit, :delete], ret)
          vu = EditTable(
            ret,
            vu,
            ["alias", "destinations"],
            fun_ref(method(:AliasPopup), "map (map, list <map>)"),
            :tab
          )
        elsif ret == :abort && Popup.ReallyAbort(Mail.touched || @edit_touched) ||
            ret == :next ||
            ret == :back
          break
        end
      end

      if ret == :next
        Mail.Touch(Mail.virtual_users != vu)
        Mail.virtual_users = deep_copy(vu)
      end
      Wizard.RestoreScreenShotName
      ret
    end

    # A Wizard Sequencer helper
    # @return	`next
    def JustNext
      :next
    end

    # Whole configuration of mail
    # @return `back, `abort or `next
    def MailSequence
      sequence = {
        "ws_start"    => "read",
        "read"        => { :abort => :abort, :next => "connection_type" },
        # common_sequence here

        # override
        "common-next" => {
          :next => "confirm"
        },
        "confirm"     => { :next => "write" },
        "write"       => { :abort => :abort, :next => :next }
      }

      Wizard.CreateDialog
      Wizard.SetDesktopTitleAndIcon("mail")

      # the second map must override the first!
      sequence = Builtins.union(@common_sequence, sequence)
      ret = Sequencer.Run(@dialogs, sequence)

      UI.CloseDialog
      Convert.to_symbol(ret)
    end

    # Whole configuration of mail but without reading and writing.
    # MTA is selected first.
    # For use with autoinstallation.
    # @return `back, `abort or `next
    def MailAutoSequence
      sequence =
        # common_sequence here
        {
          "ws_start" => "mta",
          "mta"      => { :abort => :abort, :next => "connection_type" }
        }

      # Translators: dialog caption
      caption = _("Mail configuration")
      # label
      contents = Label(_("Initializing..."))

      Wizard.CreateDialog
      Wizard.SetDesktopIcon("mail")
      Wizard.SetContentsButtons(
        caption,
        contents,
        "",
        Label.BackButton,
        Label.NextButton
      )

      # the second map must override the first!
      sequence = Builtins.union(@common_sequence, sequence)
      ret = Sequencer.Run(@dialogs, sequence)

      UI.CloseDialog
      Convert.to_symbol(ret)
    end
  end
end
