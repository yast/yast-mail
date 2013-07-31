# encoding: utf-8

# File:
#   include/mail/widgets.ycp
#
# Package:
#   Configuration of mail
#
# Summary:
#   Widget definitions.
#
# Authors:
#   Martin Vidner <mvidner@suse.cz>
#
# $Id$
module Yast
  module MailWidgetsInclude
    def initialize_mail_widgets(include_target)
      Yast.import "UI"

      textdomain "mail"

      Yast.import "Mail"
      Yast.import "MailAliases"

      Yast.import "Hostname"
      Yast.import "Address"

      Yast.import "Popup"
      Yast.import "Label"

      # ----------------------------------------------------------------

      # A list to check entered user names against.
      # It is initialized on first use.
      @local_users = nil

      # ----------------------------------------------------------------

      # A replacement for the Next button: "Finish", `next
      @finish_button = PushButton(
        Id(:next),
        Opt(:default, :key_F10),
        Label.FinishButton
      )
      #
      # **Structure:**
      #
      #     fetchmail
      #     	$[server:, protocol:, remote_user:, local_user:, password:, ...]
      @fetchmail_item = {}

      # don't forget to reset it!
      @fetchmail_item_touched = false

      # {#widget_def}
      @Widgets = {
        :foo                  => {
          "widget"   => TextEntry(),
          "opt"      => Opt(:notify),
          # optional
          "label"    => "",
          # if there are choices, they are used to construct the widget,
          # otherwise get is used
          "choices"  => [
            1,
            2,
            3
          ],
          # just a template, do not translate
          "help"     => _("."),
          "get"      => fun_ref(method(:Get_foo), "string ()"),
          "set"      => fun_ref(method(:Set_foo), "void (symbol)"),
          "validate" => fun_ref(method(:Validate_foo), "boolean (symbol)")
        },
        :outgoing_mail_server => {
          "widget"   => TextEntry(),
          # Translators: text entry label
          "label"    => _(
            "&Outgoing mail server"
          ),
          # help text
          "help"     => _(
            "\n" +
              "<p>The outgoing mail server is generally intended for dial-up connections.\n" +
              "Enter the Internet service provider's SMTP server, such as\n" +
              "<b>smtp.provider.com</b>.</p>\n"
          ),
          "get"      => fun_ref(method(:Get_outgoing_mail_server), "string ()"),
          "set"      => fun_ref(
            method(:Set_outgoing_mail_server),
            "void (symbol)"
          ),
          "validate" => fun_ref(
            method(:Validate_outgoing_mail_server),
            "boolean (symbol)"
          )
        },
        :from_header          => {
          "widget"   => TextEntry(),
          # Translators: text entry label
          "label"    => _(
            "Do&main for the 'From' header"
          ),
          # help text
          "help"     => _(
            "\n" +
              "<p>You may want the mail you sent to appear as if it originated from\n" +
              "<b>company.com</b> instead of <b>pc-042.company.com</b>.\n" +
              "Use the text box provided or a more detailed dialog.</p>\n"
          ),
          "get"      => fun_ref(method(:Get_from_header), "string ()"),
          "set"      => fun_ref(method(:Set_from_header), "void (symbol)"),
          "validate" => fun_ref(
            method(:Validate_from_header),
            "boolean (symbol)"
          )
        },
        :local_domains        => {
          "widget"   => TextEntry(),
          # Translators: text entry label
          "label"    => _(
            "&Domains for locally delivered mail"
          ),
          # help text
          "help"     => _(
            "\n" +
              "<p>Here, specify the domains for which the mail\n" +
              "will be delivered locally. If you enter nothing,\n" +
              "the local host name is assumed.</p>\n"
          ),
          "get"      => fun_ref(method(:Get_local_domains), "string ()"),
          "set"      => fun_ref(method(:Set_local_domains), "void (symbol)"),
          "validate" => fun_ref(
            method(:Validate_local_domains),
            "boolean (symbol)"
          )
        },
        :listen_remote        => {
          "widget" => CheckBox(),
          # check box label
          "label"  => _("Accept remote &SMTP connections"),
          # help text
          "help"   => _(
            "\n" +
              "<p>Mail can be received directly via the SMTP protocol\n" +
              "or it can be downloaded from\n" +
              "a POP or an IMAP server using <b>fetchmail</b>.</p>"
          ),
          "get"    => fun_ref(method(:Get_listen_remote), "boolean ()"),
          "set"    => fun_ref(method(:Set_listen_remote), "void (symbol)")
        },
        :use_amavis           => {
          "widget" => CheckBox(),
          # checkbox label
          "label"  => _("&Enable virus scanning (AMaViS)"),
          # we need notify option to enable disable dkim
          "opt"    => Opt(
            :notify
          ),
          # help text
          "help"   => _(
            "\n" +
              "<p><b>Enabling virus scanning (AMaViS)</b> checks incoming and outgoing mail\n" +
              "with AMaViS.</p>\n"
          ) +
            # help text
            _(
              "<p>Enabling AMaViS will also enable the following modules: </p>\n" +
                "<p><b>Spamassassin</b> SPAM scanner</p>\n" +
                "<p><b>DKIM</b> checks Domain Key signed incomming mails</p>\n" +
                "<p><b>Clamav</b> open source virus scanner engine</p>"
            ) +
            # help text
            _(
              "\n" +
                "<p>If AMaViS is not installed and you want to use it, it will be installed\n" +
                "automatically.</p>\n"
            ),
          "get"    => fun_ref(method(:Get_use_amavis), "boolean ()"),
          "set"    => fun_ref(method(:Set_use_amavis), "void (symbol)")
        },
        :use_dkim             => {
          "widget" => CheckBox(),
          # checkbox label
          "label"  => _(
            "&Enable DKIM signing for outgoing mails."
          ),
          # help text
          "help"   => _(
            "\n<p><b>Enabling DKIM signig for outgoing mails.</b></p>\n"
          ) +
            # help text
            _(
              "\n" +
                "<p>Enabling DKIM for outgoing emails requires additional actions. A SSL key\n" +
                "will be generated for the 'mydomain' value defined in Postfix. A new service\n" +
                "'submission' will be configured in Postfix. After this is set up you can send\n" +
                "email with this service 'submission' from 'mynetworks' with enabled SASL\n" +
                "authentication. Only the emails sent by this new service will be signed with\n" +
                "the domain key.</p>\n"
            ) +
            # help text
            _(
              "\n" +
                "<p>The public key of the domain key needs to be offered by a Domain Name\n" +
                "Service. The public key will be saved as a DNS TXT record\n" +
                "in <b>/var/db/dkim/[mydomain].public.txt</b> and needs to be deployed to an\n" +
                "according Domain Name Service. If there is a name service\n" +
                "running on this server, which is the authoritative server for that domain, the\n" +
                "public key will be added as a TXT record to that domain zone\n" +
                "automatically.</p>\n"
            ) +
            # help text
            _(
              "If you enable DKIM support, the virus scanning (AMaViS) will be enabled too."
            ),
          "get"    => fun_ref(method(:Get_use_dkim), "boolean ()"),
          "set"    => fun_ref(method(:Set_use_dkim), "void (symbol)")
        },
        :fm_server            => {
          "widget"   => TextEntry(),
          # Translators: text entry label
          "label"    => _("&Server"),
          "help"     => "",
          "get"      => fun_ref(method(:Get_fm_server), "string ()"),
          "set"      => fun_ref(method(:Set_fm_server), "void (symbol)"),
          "validate" => fun_ref(method(:Validate_fm_server), "boolean (symbol)")
        },
        :fm_protocol          => {
          "widget"  => ComboBox(),
          "opt"     => Opt(:hstretch),
          # Translators: combo box label
          "label"   => _("&Protocol"),
          "choices" => fun_ref(method(:Choices_protocol), "list ()"),
          "help"    => "",
          "get"     => fun_ref(method(:Get_fm_protocol), "string ()"),
          "set"     => fun_ref(method(:Set_fm_protocol), "void (symbol)")
        },
        :fm_remote_user       => {
          "widget"   => TextEntry(),
          # Translators: text entry label
          "label"    => _("&Remote user name"),
          "help"     => "",
          "get"      => fun_ref(method(:Get_fm_remote_user), "string ()"),
          "set"      => fun_ref(method(:Set_fm_remote_user), "void (symbol)"),
          "validate" => fun_ref(
            method(:Validate_fm_remote_user),
            "boolean (symbol)"
          )
        },
        :fm_password          => {
          "widget" => Password(),
          # Translators: text entry label
          "label"  => _("P&assword"),
          "help"   => "",
          "get"    => fun_ref(method(:Get_fm_password), "string ()"),
          "set"    => fun_ref(method(:Set_fm_password), "void (symbol)")
        },
        :fm_local_user        => {
          "widget"   => ComboBox(),
          # editable because entering a mail alias makes sense too
          # and we miss the nis users
          "opt"      => Opt(
            :hstretch,
            :editable
          ),
          # Translators: combo box label
          "label"    => _("&Local user"),
          "choices"  => fun_ref(method(:Choices_local_user), "list ()"),
          "help"     => "",
          "get"      => fun_ref(method(:Get_fm_local_user), "string ()"),
          "set"      => fun_ref(method(:Set_fm_local_user), "void (symbol)"),
          "validate" => fun_ref(
            method(:Validate_fm_local_user),
            "boolean (symbol)"
          )
        },
        :root_alias           => {
          "widget"   => TextEntry(),
          # Translators: text entry label
          "label"    => _(
            "&Forward root's mail to"
          ),
          # help text
          "help"     => _(
            "<p>It is recommended to have a regular user account\nfor the system administrator and redirect root's mail to this account.</p>"
          ),
          "get"      => fun_ref(method(:Get_root_alias), "string ()"),
          "set"      => fun_ref(method(:Set_root_alias), "void (symbol)"),
          "validate" => fun_ref(
            method(:Validate_root_alias),
            "boolean (symbol)"
          )
        },
        :delivery_mode        => {
          "widget"   => ComboBox(),
          "opt"      => Opt(:hstretch),
          # Translators: combo box label
          # /etc/sysconfig/postfix: POSTFIX_MDA
          "label"    => _(
            "&Delivery Mode"
          ),
          "choices"  => fun_ref(method(:Choices_delivery_mode), "list ()"),
          # help text
          "help"     => _(
            "<p>The <b>delivery mode</b> is usually <b>Directly</b>, unless you do not forward root's mail or want to access the mail via IMAP.</p>"
          ),
          "get"      => fun_ref(method(:Get_delivery_mode), "symbol ()"),
          "set"      => fun_ref(method(:Set_delivery_mode), "void (symbol)"),
          "validate" => fun_ref(
            method(:Validate_delivery_mode),
            "boolean (symbol)"
          )
        }
      }
    end

    # ----------------------------------------------------------------

    # See RFC 2822, 3.4
    # But for now, nonempty, no-spaces.
    # @param [String] address an address to check
    # @return valid?
    def check_mail_local_part(address)
      address != "" && Builtins.findfirstof(address, " ") == nil
    end

    # Read user names from passwd.
    # It does not get the NIS entries, that's why one combo is editable.
    # "+" is filtered out.
    # @return user name list
    def GetLocalUsers
      if @local_users == nil
        # initialize the list
        Yast.import "Users"
        Yast.import "UsersCache"
        Yast.import "Ldap"

        UI.OpenDialog(
          VBox(
            # LogView label. take a string from users?
            LogView(
              Id(:progress),
              _("Reading the &User List"),
              # visible, max
              4,
              10
            ),
            VSpacing(1)
          )
        )

        Users.SetGUI(false)
        @local_users = []

        UI.ChangeWidget(
          Id(:progress),
          :LastLine,
          # LogView progress line
          _("Local users") + "\n"
        )
        Users.Read
        @local_users = Builtins.flatten(
          [
            @local_users,
            UsersCache.GetUsernames("local"),
            UsersCache.GetUsernames("system")
          ]
        )

        if Users.LDAPAvailable
          UI.ChangeWidget(
            Id(:progress),
            :LastLine,
            # LogView progress line
            _("LDAP users") + "\n"
          )

          if Users.LDAPNotRead
            # open the popup that asks for password (or anonymous access)
            #if (Ldap::bind_pass == nil)
            #    Ldap::SetBindPassword (Ldap::GetLDAPPassword (true));
            # alternatively, force anonymous access:
            Ldap.SetAnonymous(true)
            Users.ReadNewSet("ldap")
          end
          @local_users = Builtins.flatten(
            [@local_users, UsersCache.GetUsernames("ldap")]
          )
        end

        if Users.NISAvailable
          UI.ChangeWidget(
            Id(:progress),
            :LastLine,
            # LogView progress line
            _("NIS users") + "\n"
          )
          Users.ReadNewSet("nis")
          @local_users = Builtins.flatten(
            [@local_users, UsersCache.GetUsernames("nis")]
          )
        end

        Users.SetGUI(true) # reenables Report
        UI.CloseDialog
      end
      deep_copy(@local_users)
    end


    # ----------------------------------------------------------------

    # Formats a list for a TextEntry, separating the elements by ", "
    # @param [Array<String>] alist	a list
    # @return	a string
    def listToString(alist)
      alist = deep_copy(alist)
      Builtins.mergestring(alist, ", ")
    end

    # Splits a TextEntry string into a list of strings
    # separated by spaces, commas or semicolons.
    # Empty strings are removed.
    # @param [String] astring	a string
    # @return		a list of strings
    def stringToList(astring)
      alist = Builtins.splitstring(astring, " ,;")
      Builtins.filter(alist) { |s| s != "" }
    end


    # (sample)
    # @return a variable to be used by a widget
    def Get_foo
      Ops.get_string(@fetchmail_item, "protocol", "")
    end

    # (sample)
    # Set a variable acording to widget value
    # @param [Symbol] id widget id
    def Set_foo(id)
      val = Convert.to_string(UI.QueryWidget(Id(id), :Value))
      @fetchmail_item_touched = @fetchmail_item_touched ||
        Ops.get_string(@fetchmail_item, "protocol", "") != val
      @fetchmail_item = Builtins.add(@fetchmail_item, "protocol", val)

      nil
    end

    # (sample)
    # Validate widget value
    # @param [Symbol] id widget id
    # @return valid?
    def Validate_foo(id)
      val = Convert.to_string(UI.QueryWidget(Id(id), :Value))
      if !Hostname.CheckDomain(val)
        UI.SetFocus(Id(id))
        # Translators: error popup
        msg = _("The host name is incorrect")
        Popup.Error(msg)
        return false
      end
      true
    end

    # @return a variable to be used by a widget
    def Get_outgoing_mail_server
      Mail.outgoing_mail_server
    end

    # Set a variable acording to widget value
    # @param [Symbol] id widget id
    def Set_outgoing_mail_server(id)
      oms = Convert.to_string(UI.QueryWidget(Id(id), :Value))
      Mail.Touch(Mail.outgoing_mail_server != oms)
      Mail.outgoing_mail_server = oms

      nil
    end

    # Validate widget value
    # @param [Symbol] id widget id
    # @return valid?
    def Validate_outgoing_mail_server(id)
      # when validating: may be enclosed in brackets (prevents mx lookups)
      oms = Convert.to_string(UI.QueryWidget(Id(id), :Value))
      # watch this: "[", no brackets, "]"
      oms_no_brackets = Builtins.regexpmatch(oms, "[[][^][]*[]]:.*") ?
        Builtins.regexpsub(oms, ".(.*).:.*", "\\1") :
        oms

      if oms_no_brackets == oms
        oms_no_brackets = Builtins.regexpmatch(oms, "[[][^][]*[]]") ?
          Builtins.regexpsub(oms, ".(.*).", "\\1") :
          oms
      end
      if oms_no_brackets == oms
        oms_no_brackets = Builtins.regexpmatch(oms, ".*:.*") ?
          Builtins.regexpsub(oms, "(.*):.*", "\\1") :
          oms
      end

      if oms_no_brackets != "" && !Address.Check(oms_no_brackets) ||
          oms_no_brackets == "" && Mail.connection_type == :dialup
        UI.SetFocus(Id(id))
        Popup.Error(Address.Valid4)
        return false
      end
      true
    end


    # @return a variable to be used by a widget
    def Get_from_header
      Mail.from_header
    end

    # Set a variable acording to widget value
    # @param [Symbol] id widget id
    def Set_from_header(id)
      fh = Convert.to_string(UI.QueryWidget(Id(id), :Value))
      Mail.Touch(Mail.from_header != fh)
      Mail.from_header = fh

      nil
    end

    def Validate_from_header(id)
      fh = Convert.to_string(UI.QueryWidget(Id(id), :Value))
      if fh != "" && !Hostname.CheckDomain(fh)
        UI.SetFocus(Id(id))
        Popup.Error(Hostname.ValidDomain)
        return false
      end
      true
    end

    # @return a variable to be used by a widget
    def Get_local_domains
      listToString(Mail.local_domains)
    end

    # Set a variable acording to widget value
    # @param [Symbol] id widget id
    def Set_local_domains(id)
      lld = stringToList(Convert.to_string(UI.QueryWidget(Id(id), :Value)))
      Mail.Touch(Mail.local_domains != lld)
      Mail.local_domains = deep_copy(lld)

      nil
    end

    # Validate widget value
    # @param [Symbol] id widget id
    # @return valid?
    def Validate_local_domains(id)
      lld = stringToList(Convert.to_string(UI.QueryWidget(Id(id), :Value)))
      # find one that fails
      if Builtins.find(lld) do |s|
          # #36871
          # Strip \$ which marks postfix substitutions:
          # Verify that they only occur together
          # and then remove them individually. Elementary, dear Watson.
          if Builtins.regexpmatch(s, "\\\\[^$]") ||
              Builtins.regexpmatch(s, "\\\\$") ||
              Builtins.regexpmatch(s, "[^\\]\\$") ||
              Builtins.regexpmatch(s, "^\\$")
            next true
          end
          s = Builtins.deletechars(s, "\\$")
          !Hostname.CheckDomain(s)
        end != nil
        UI.SetFocus(Id(id))
        Popup.Error(Hostname.ValidDomain)
        return false
      end
      true
    end

    # @return a variable to be used by a widget
    def Get_listen_remote
      Mail.listen_remote
    end

    # Set a variable acording to widget value
    # @param [Symbol] id widget id
    def Set_listen_remote(id)
      lr = Convert.to_boolean(UI.QueryWidget(Id(id), :Value))
      Mail.Touch(Mail.listen_remote != lr)
      Mail.listen_remote = lr

      nil
    end

    # @return a variable to be used by a widget
    def Get_use_amavis
      Mail.use_amavis
    end

    # Set a variable acording to widget value
    # @param [Symbol] id widget id
    def Set_use_amavis(id)
      am = Convert.to_boolean(UI.QueryWidget(Id(id), :Value))
      Mail.Touch(Mail.use_amavis != am)
      Mail.use_amavis = am

      nil
    end

    # @return a variable to be used by a widget
    def Get_use_dkim
      Mail.use_dkim
    end

    # Set a variable acording to widget value
    # @param [Symbol] id widget id
    def Set_use_dkim(id)
      dkim = Convert.to_boolean(UI.QueryWidget(Id(id), :Value))
      Mail.Touch(Mail.use_dkim != dkim)
      Mail.use_dkim = dkim

      nil
    end


    # @return a variable to be used by a widget
    def Get_fm_server
      Ops.get_string(@fetchmail_item, "server", "")
    end

    # Set a variable acording to widget value
    # @param [Symbol] id widget id
    def Set_fm_server(id)
      val = Convert.to_string(UI.QueryWidget(Id(id), :Value))
      @fetchmail_item_touched = @fetchmail_item_touched ||
        Ops.get_string(@fetchmail_item, "server", "") != val
      @fetchmail_item = Builtins.add(@fetchmail_item, "server", val)

      nil
    end

    # also used for smtp_auth server
    # Validate widget value
    # @param [Symbol] id widget id
    # @return valid?
    def Validate_fm_server(id)
      val = Convert.to_string(UI.QueryWidget(Id(id), :Value))
      if !Hostname.CheckDomain(val)
        UI.SetFocus(Id(id))
        # Translators: error popup
        msg = _("The host name is incorrect")
        Popup.Error(msg)
        return false
      end
      true
    end

    # @return a variable to be used by a widget
    def Get_fm_protocol
      Ops.get_string(@fetchmail_item, "protocol", "AUTO")
    end

    # Set a variable acording to widget value
    # @param [Symbol] id widget id
    def Set_fm_protocol(id)
      val = Convert.to_string(UI.QueryWidget(Id(id), :Value))
      @fetchmail_item_touched = @fetchmail_item_touched ||
        Ops.get_string(@fetchmail_item, "protocol", "") != val
      @fetchmail_item = Builtins.add(@fetchmail_item, "protocol", val)

      nil
    end

    # @return a variable to be used by a widget
    def Get_fm_remote_user
      Ops.get_string(@fetchmail_item, "remote_user", "")
    end

    # Set a variable acording to widget value
    # @param [Symbol] id widget id
    def Set_fm_remote_user(id)
      val = Convert.to_string(UI.QueryWidget(Id(id), :Value))
      @fetchmail_item_touched = @fetchmail_item_touched ||
        Ops.get_string(@fetchmail_item, "remote_user", "") != val
      @fetchmail_item = Builtins.add(@fetchmail_item, "remote_user", val)

      nil
    end

    # also used for smtp_auth user
    # Validate widget value
    # @param [Symbol] id widget id
    # @return valid?
    def Validate_fm_remote_user(id)
      val = Convert.to_string(UI.QueryWidget(Id(id), :Value))
      if val == ""
        UI.SetFocus(Id(id))
        # Translators: error popup
        Popup.Error(_("The user name format is incorrect."))
        return false
      end
      true
    end

    # @return a variable to be used by a widget
    def Get_fm_password
      Ops.get_string(@fetchmail_item, "password", "")
    end

    # Set a variable acording to widget value
    # @param [Symbol] id widget id
    def Set_fm_password(id)
      val = Convert.to_string(UI.QueryWidget(Id(id), :Value))
      @fetchmail_item_touched = @fetchmail_item_touched ||
        Ops.get_string(@fetchmail_item, "password", "") != val
      @fetchmail_item = Builtins.add(@fetchmail_item, "password", val)

      nil
    end


    # @return a variable to be used by a widget
    def Get_fm_local_user
      Ops.get_string(@fetchmail_item, "local_user", "")
    end

    # Set a variable acording to widget value
    # @param [Symbol] id widget id
    def Set_fm_local_user(id)
      val = Convert.to_string(UI.QueryWidget(Id(id), :Value))
      @fetchmail_item_touched = @fetchmail_item_touched ||
        Ops.get_string(@fetchmail_item, "local_user", "") != val
      @fetchmail_item = Builtins.add(@fetchmail_item, "local_user", val)

      nil
    end

    # Validate widget value
    # @param [Symbol] id widget id
    # @return valid?
    def Validate_fm_local_user(id)
      val = Convert.to_string(UI.QueryWidget(Id(id), :Value))
      if !check_mail_local_part(val)
        # it may be ok if it is directed to an alias
        UI.SetFocus(Id(id))
        # Translators: error popup
        Popup.Error(_("The user name format is incorrect."))
        return false
      end
      true
    end

    # @return a variable to be used by a widget
    def Get_root_alias
      MailAliases.root_alias
    end

    # Set a variable acording to widget value
    # @param [Symbol] id widget id
    def Set_root_alias(id)
      val = Convert.to_string(UI.QueryWidget(Id(id), :Value))
      Mail.Touch(MailAliases.root_alias != val)
      MailAliases.root_alias = val

      nil
    end

    # Validate widget value
    # @param [Symbol] id widget id
    # @return valid?
    def Validate_root_alias(id)
      val = Convert.to_string(UI.QueryWidget(Id(id), :Value))
      # user@machine, \\root - too much variation, don't check yet
      if false
        UI.SetFocus(Id(id))
        # Translators: error popup
        Popup.Error(_("The user name format is incorrect."))
        return false
      end
      true
    end

    # @return a variable to be used by a widget
    def Get_delivery_mode
      scr2ui = {
        :local    => :dm_local,
        :procmail => :dm_procmail,
        :cyrus    => :dm_cyrus
      }
      val = Ops.get_symbol(scr2ui, Mail.postfix_mda, :dm_local)
      val
    end

    # Set a variable acording to widget value
    # @param [Symbol] id widget id
    def Set_delivery_mode(id)
      val = Convert.to_symbol(UI.QueryWidget(Id(id), :Value))
      ui2scr = {
        :dm_local    => :local,
        :dm_procmail => :procmail,
        :dm_cyrus    => :cyrus
      }
      val = Ops.get_symbol(ui2scr, val, :local)
      Mail.Touch(Mail.postfix_mda != val)
      Mail.postfix_mda = val

      nil
    end

    # Validate widget value
    # @param [Symbol] id widget id
    # @return valid?
    def Validate_delivery_mode(id)
      val = Convert.to_symbol(UI.QueryWidget(Id(id), :Value))
      # Procmail is only OK if root has an alias
      # Because postfix runs procmail as nobody instead of root
      # and the mail would end up in the wrong place
      ok = true

      # the root alias widget should be in the same dialog!
      ra_id = :root_alias
      if !UI.WidgetExists(Id(ra_id))
        Builtins.y2error(
          "Widget %1 not found, skipping validation of %2",
          ra_id,
          id
        )
      else
        ra_val = Convert.to_string(UI.QueryWidget(Id(ra_id), :Value))
        ok = false if ra_val == "" && val == :dm_procmail
      end

      if !ok
        UI.SetFocus(Id(id))
        # Translators: error popup
        # Validation
        Popup.Error(_("Cannot use procmail when root's mail is not forwarded."))
        return false
      end
      true
    end

    # @return [Array] of choides for a combo box
    def Choices_protocol
      deep_copy(Mail.protocol_choices)
    end

    # @return [Array] of choides for a combo box
    def Choices_local_user
      GetLocalUsers()
    end

    # @return [Array] of choides for a combo box
    def Choices_delivery_mode
      # TODO: should check whether cyrus-imapd is installed.
      # And show the choice only if it is.
      # But config.postfix falls back to local if it's not, so OK
      [
        # combo box choice:
        # deliver mail normally
        Item(Id(:dm_local), _("Directly")),
        # combo box choice:
        # deliver mail through procmail
        Item(Id(:dm_procmail), _("Through procmail")),
        # combo box choice:
        # deliver mail to cyrus-imapd using LMTP
        Item(Id(:dm_cyrus), _("To Cyrus IMAP Server"))
      ]
    end
  end
end
