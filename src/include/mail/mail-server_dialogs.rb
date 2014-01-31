# encoding: utf-8

# File:	clients/mail-server.ycp
# Package:	Configuration of mail-server
# Summary:	Main file
# Authors:	Peter Varkoly <varkoly@suse.de>
#
# $Id: mail-server.ycp 19955 2004-10-26 12:28:16Z varkoly $
#
# Main file for mail-server configuration. Uses all other files.
module Yast
  module MailMailServerDialogsInclude
    def initialize_mail_mail_server_dialogs(include_target)
      textdomain "mail"

      Yast.import "Label"
      Yast.import "Ldap"
      Yast.import "Wizard"
      Yast.import "Report"
      Yast.import "Service"
      Yast.import "Users"
      Yast.import "YaPI::MailServer"

      Yast.include include_target, "mail/helps.rb"
    end

    def ReallyAbort
      !MailServer.Modified || Popup.ReallyAbort(true)
    end

    # CheckLDAPDialog
    # Checking the LDAP Configuration
    # @return dialog result
    def CheckLDAPDialog
      Builtins.y2milestone("--Start CheckLDAPDialog ---")
      abort_block = lambda { false }
      ca_mgm = false
      conf_ldap_client = false
      setup_ldap_server = false
      ldap_server_local = false
      comment = ""
      Ldap.Read
      _LDAPSettings = Convert.convert(
        Ldap.Export,
        :from => "map",
        :to   => "map <string, any>"
      )
      args = []
      size1 = Convert.to_integer(
        SCR.Read(path(".target.size"), "/etc/ssl/servercerts/servercert.pem")
      )
      size2 = Convert.to_integer(
        SCR.Read(path(".target.size"), "/etc/ssl/servercerts/serverkey.pem")
      )
      if Ops.less_or_equal(size1, 0) || Ops.less_or_equal(size2, 0)
        ca_mgm = true
      end
      Builtins.y2milestone(" LDAPSettings %1", _LDAPSettings)
      #if( ! LDAPSettings["start_ldap"]:false )
      if Ops.get_string(_LDAPSettings, "bind_dn", "") == ""
        setup_ldap_server = true
        conf_ldap_client = true
        ldap_server_local = true
        comment = _("Your computer is not configured as an LDAP client.") + "<br>" +
          _("We suggest you set up a local LDAP server for the mail server.") + "<br>" +
          _(
            "Create certificates for the LDAP and mail server in order to secure your system."
          ) + "<br>"
      else
        if Ops.get_string(_LDAPSettings, "ldap_server", "") == "127.0.0.1" ||
            Ops.get_string(_LDAPSettings, "ldap_server", "") == "localhost"
          comment = Ops.add(
            Ops.add(
              _(
                "Your computer is configured as an LDAP client and the LDAP server is local."
              ) + "<br>" +
                _(
                  "We suggest you adapt the LDAP server configuration for the mail server."
                ) + "<br>" +
                _(
                  "For this reason you have to know the password of the LDAP administrator account:"
                ) + "<br>" + "<B>",
              Ops.get_string(_LDAPSettings, "bind_dn", "")
            ),
            ".</B><BR>"
          )
          ldap_server_local = true
        else
          comment = Ops.add(
            Ops.add(
              Ops.add(
                _(
                  "Your computer is configured as a LDAP client and the LDAP server is not local."
                ) + "<br>" +
                  _(
                    "We suggest you configure the LDAP server for the mail server."
                  ) + "<br>" +
                  _(
                    "For this reason you have to know the password of the LDAP administrator account:"
                  ) + "<br>" + "<B>",
                Ops.get_string(_LDAPSettings, "bind_dn", "")
              ),
              ".</B><BR>"
            ),
            _(
              "Furthermore, the LDAP server has to contain the <b>suse-mailserver.schema</b> and the corresponding index entries."
            )
          )
        end
      end

      # Now we create the dialog:
      d = HBox(
        VBox(
          HSpacing(60),
          VSpacing(0.2),
          RichText(comment),
          VSpacing(0.2),
          Left(CheckBox(Id(:ca_mgm), _("Create certificates."), ca_mgm)),
          VSpacing(0.2),
          Left(
            CheckBox(
              Id(:setup_ldap_server),
              _("Set up a local LDAP server."),
              setup_ldap_server
            )
          ),
          VSpacing(0.2),
          Left(
            CheckBox(
              Id(:conf_ldap_client),
              _("Configure dedicated LDAP server."),
              conf_ldap_client
            )
          ),
          HBox(
            PushButton(Id(:abort), Label.AbortButton),
            PushButton(Id(:next), Label.NextButton)
          )
        )
      )
      UI.OpenDialog(Opt(:decorated), d)
      ui = UI.UserInput
      setup_ldap_server = Convert.to_boolean(
        UI.QueryWidget(Id(:setup_ldap_server), :Value)
      )
      ca_mgm = Convert.to_boolean(UI.QueryWidget(Id(:ca_mgm), :Value))
      conf_ldap_client = Convert.to_boolean(
        UI.QueryWidget(Id(:conf_ldap_client), :Value)
      )
      UI.CloseDialog
      return deep_copy(ui) if ui == :abort

      args = Builtins.add(args, "ca_mgm") if ca_mgm
      Progress.NextStage
      args = Builtins.add(args, "setup") if setup_ldap_server
      if conf_ldap_client && !setup_ldap_server
        args = Builtins.add(args, "conf")
      end
      args = Builtins.add(args, "local") if ldap_server_local
      Progress.NextStage
      if setup_ldap_server || ca_mgm || conf_ldap_client || ldap_server_local
        WFM.CallFunction("mail-server_ldap-setup", args)
        Ldap.Read
        Ldap.LDAPInit
        _LDAPSettings = Convert.convert(
          Ldap.Export,
          :from => "map",
          :to   => "map <string, any>"
        )
        #tell Ldap module to create the default objects:
        Ops.set(_LDAPSettings, "start_ldap", true)
        Ops.set(_LDAPSettings, "create_ldap", true)
        Ldap.Import(_LDAPSettings)
        #write the settings:
        Ldap.Write(abort_block)
      else
        Ldap.LDAPInit
      end

      MailServer.AdminPassword = Ldap.LDAPAskAndBind(false)
      if MailServer.AdminPassword != nil
        abort = lambda do
          if UI.PollInput == :abort &&
              # popup text
              Popup.YesNo(_("Really abort the writing process?"))
            next true
          end
          false
        end

        #create default mail-server configuration
        YaPI::MailServer.ResetMailServer(MailServer.AdminPassword)
        return :ok
      else
        return :abort
      end
    end

    # AuthorizingDialog
    # The adminstrator user will be authorized
    # @return dialog result
    def AuthorizingDialog
      Builtins.y2milestone("--Start AuthorizingDialog ---")
      Ldap.Read
      _LDAPSettings = Ldap.Export
      if Ops.get_string(_LDAPSettings, "bind_dn", "") == ""
        _ERROR = _("You must configure LDAP to use the mail server.") + "\n" +
          _(" The LDAP configuration starts now.")
        if Popup.YesNo(_ERROR)
          return :ldapsetup
        else
          return :abort
        end
      end
      Ldap.LDAPInit

      size1 = Convert.to_integer(
        SCR.Read(path(".target.size"), "/etc/ssl/servercerts/servercert.pem")
      )
      size2 = Convert.to_integer(
        SCR.Read(path(".target.size"), "/etc/ssl/servercerts/serverkey.pem")
      )
      if Ops.less_or_equal(size1, 0) || Ops.less_or_equal(size2, 0)
        Popup.Warning(
          _(
            "You have not created server certificate and key.\n" +
              "You will not able to use server side SSL and TSL on the mail server.\n" +
              "Create the certificate with the YaST2 CA management module.\n"
          )
        )
      else
        MailServer.CertExist = true
      end

      if MailServer.AdminPassword == nil
        MailServer.AdminPassword = Ldap.LDAPAskAndBind(false)
      end
      return :abort if MailServer.AdminPassword == nil
      :next
    end

    def GenerateTree(_Tree, parent, input)
      _Tree = deep_copy(_Tree)
      input = deep_copy(input)
      Builtins.foreach(input) do |i|
        title = Ops.get_string(i, 0, "")
        itemid = Ops.get_string(i, 1, "")
        children = Ops.get_list(i, 2, [])
        _Tree = Wizard.AddTreeItem(_Tree, parent, title, itemid)
        if Ops.greater_than(Builtins.size(children), 0)
          _Tree = GenerateTree(_Tree, title, children)
        end
      end
      deep_copy(_Tree)
    end

    def GlobalSettingsDialog
      Builtins.y2milestone("--Start GlobalSettingsDialog ---")
      limit = Ops.get_string(MailServer.GlobalSettings, "MaximumMailSize", "0") != "0"
      is_DNS = Ops.get_string(
        MailServer.GlobalSettings,
        ["SendingMail", "Type"],
        ""
      ) == "DNS"
      is_NONE = Ops.get_string(
        MailServer.GlobalSettings,
        ["SendingMail", "Type"],
        ""
      ) == "NONE"
      is_RELAY = Ops.get_string(
        MailServer.GlobalSettings,
        ["SendingMail", "Type"],
        ""
      ) == "relayhost"
      _TLS_NONE = Ops.get_string(
        MailServer.GlobalSettings,
        ["SendingMail", "TLS"],
        ""
      ) == "NONE"
      _TLS_MAY = Ops.get_string(
        MailServer.GlobalSettings,
        ["SendingMail", "TLS"],
        ""
      ) == "MAY"
      _TLS_MUST = Ops.get_string(
        MailServer.GlobalSettings,
        ["SendingMail", "TLS"],
        ""
      ) == "MUST"
      _TLS_MUSTN = Ops.get_string(
        MailServer.GlobalSettings,
        ["SendingMail", "TLS"],
        ""
      ) == "MUST_NOPEERMATCH"
      auth = Ops.get_string(
        MailServer.GlobalSettings,
        ["SendingMail", "RelayHost", "Auth"],
        "0"
      ) == "1"
      hostname = Ops.get_string(
        MailServer.GlobalSettings,
        ["SendingMail", "RelayHost", "Name"],
        ""
      )
      account = Ops.get_string(
        MailServer.GlobalSettings,
        ["SendingMail", "RelayHost", "Account"],
        ""
      )
      password = Ops.get_string(
        MailServer.GlobalSettings,
        ["SendingMail", "RelayHost", "Password"],
        ""
      )

      # I don't know if it hase a sence to use MUST_NOPEERMATCH.
      _TLS_MUST = _TLS_MUSTN if _TLS_MUSTN

      security = HBox(
        Left(RadioButton(Id("NONE"), _("Do Not Use TLS"), _TLS_NONE)), #                  ,`Left(`RadioButton(`id("MUST_NOPEERMATCH"), _("Use TLS but do not check CA"), TLS_MUSTN))
        Left(RadioButton(Id("MAY"), _("Use TLS If Possible"), _TLS_MAY)),
        Left(RadioButton(Id("MUST"), _("Enforce TLS"), _TLS_MUST))
      )
      if is_NONE
        security = HBox(
          Opt(:disabled), #                  ,`Left(`RadioButton(`id("MUST_NOPEERMATCH"), _("Use TLS but do not check CA"), TLS_MUSTN))
          Left(RadioButton(Id("NONE"), _("Do Not Use TLS"), _TLS_NONE)),
          Left(RadioButton(Id("MAY"), _("Use TLS If Possible"), _TLS_MAY)),
          Left(RadioButton(Id("MUST"), _("Enforce TLS"), _TLS_MUST))
        )
      end

      relayhost = HBox(
        HSpacing(3),
        VBox(
          Left(
            CheckBox(
              Id(:RelayHostAuth),
              Opt(:notify),
              _("Relay Host Requires Authentication"),
              auth
            )
          ),
          HBox(
            TextEntry(Id(:RelayHostName), _("Host Name or IP"), hostname),
            TextEntry(Id(:RelayHostAccount), _("Account"), account)
          ),
          HBox(
            Password(Id(:Password1), _("Password"), password),
            Password(Id(:Password2), _("Confirm Password"), password)
          )
        )
      )
      if is_RELAY && !auth
        relayhost = HBox(
          HSpacing(3),
          VBox(
            Left(
              CheckBox(
                Id(:RelayHostAuth),
                Opt(:notify),
                _("Relay Host Requires Authentication"),
                auth
              )
            ),
            HBox(
              TextEntry(Id(:RelayHostName), _("Host Name or IP"), hostname),
              TextEntry(
                Id(:RelayHostAccount),
                Opt(:disabled),
                _("Account"),
                account
              )
            ),
            HBox(
              Password(Id(:Password1), Opt(:disabled), _("Password"), password),
              Password(
                Id(:Password2),
                Opt(:disabled),
                _("Confirm Password"),
                password
              )
            )
          )
        )
      elsif !is_RELAY
        relayhost = HBox(
          HSpacing(3),
          VBox(
            Left(
              CheckBox(
                Id(:RelayHostAuth),
                Opt(:disabled),
                _("Relay Host Requires Authentication"),
                auth
              )
            ),
            HBox(
              TextEntry(
                Id(:RelayHostName),
                Opt(:disabled),
                _("Host Name or IP"),
                hostname
              ),
              TextEntry(
                Id(:RelayHostAccount),
                Opt(:disabled),
                _("Account"),
                account
              )
            ),
            HBox(
              Password(Id(:Password1), Opt(:disabled), _("Password"), password),
              Password(
                Id(:Password2),
                Opt(:disabled),
                _("Confirm Password"),
                password
              )
            )
          )
        )
      end


      _MaximumMailSize = nil
      if !limit
        _MaximumMailSize = TextEntry(
          Id(:MaximumMailSize),
          Opt(:disabled),
          "",
          "0"
        )
      else
        # We need the Mail Size in kb
        _MMS = Builtins.tointeger(
          Ops.get_string(MailServer.GlobalSettings, "MaximumMailSize", "0")
        )
        if Ops.greater_than(_MMS, 0) && Ops.less_than(_MMS, 1024)
          _MMS = 1
          Ops.set(MailServer.GlobalSettings, "Changed", true)
        else
          _MMS = Ops.divide(_MMS, 1024)
        end
        _MaximumMailSize = TextEntry(
          Id(:MaximumMailSize),
          "",
          Builtins.sformat("%1", _MMS)
        )
      end

      content = VBox(
        TextEntry(
          Id(:Banner),
          _("Server Identification"),
          Ops.get_string(
            MailServer.GlobalSettings,
            "Banner",
            "SuSE Linux Mail Server"
          )
        ),
        VStretch(),
        Frame(
          _("Mail Size"),
          RadioButtonGroup(
            Id(:MailSize),
            HBox(
              HWeight(
                2,
                RadioButton(
                  Id("MailSizeNoLimit"),
                  Opt(:notify),
                  _("No Limit"),
                  !limit
                )
              ),
              HWeight(
                3,
                RadioButton(
                  Id("MailSizeLimit"),
                  Opt(:notify),
                  _("Maximum Mail Size"),
                  limit
                )
              ),
              HWeight(2, _MaximumMailSize),
              HWeight(1, Label(_("KByte")))
            )
          )
        ),
        VStretch(),
        Frame(
          _("Outgoing Mails"),
          VBox(
            RadioButtonGroup(
              Id(:SendingMailType),
              VBox(
                HBox(
                  Left(
                    RadioButton(
                      Id("DNS"),
                      Opt(:notify),
                      _("Direct Delivery (DNS)"),
                      is_DNS
                    )
                  ),
                  Left(
                    RadioButton(
                      Id("NOOUT"),
                      Opt(:notify),
                      _("No Outgoing Mail"),
                      is_NONE
                    )
                  )
                ),
                Left(
                  RadioButton(
                    Id("relayhost"),
                    Opt(:notify),
                    _("Use Relay Host"),
                    is_RELAY
                  )
                ),
                relayhost
              )
            ),
            VStretch(),
            RadioButtonGroup(
              Id(:SendingMailTLS),
              HBox(HStretch(), Frame(_("Security"), security), HStretch())
            )
          )
        )
      )

      deep_copy(content)
    end

    def MakeSelectedList(items, value)
      items = deep_copy(items)
      _SelectedList = []
      Builtins.foreach(items) do |i|
        if i == value
          _SelectedList = Builtins.add(_SelectedList, Item(Id(i), i, true))
        else
          _SelectedList = Builtins.add(_SelectedList, Item(Id(i), i))
        end
      end
      deep_copy(_SelectedList)
    end

    def ShowMailTransport(_CID, _ACTION)
      Builtins.y2milestone("--Start ShowMailTransport ---")
      _Transports = Ops.get_list(MailServer.MailTransports, "Transports", [])
      _TLSSites = Ops.get_map(MailServer.MailTransports, "TLSSites", {})
      _SASLAccounts = Ops.get_map(MailServer.MailTransports, "SASLAccounts", {})
      _Destination = ""
      _Subdomains = true
      _Protocol = "smtp"
      _Protocols = ["smtp", "uucp", "error"]
      _Server = ""
      _NOMX = true
      _TLS = ""
      _Auth = false
      _Account = ""
      _Password = ""
      _TransportTLSnone = false
      _TransportTLSuse = true
      _TransportTLSenforce = false
      _TransportID = ""

      main = VBox(
        Left(TextEntry(Id(:Destination), _("Destination"), _Destination)),
        Left(CheckBox(Id(:Subdomains), _("With Subdomains"), _Subdomains)),
        Left(
          ComboBox(
            Id(:Protocol),
            Opt(:editable),
            _("Transport"),
            MakeSelectedList(_Protocols, _Protocol)
          )
        ),
        Left(TextEntry(Id(:Server), _("Server"), _Server)),
        Left(CheckBox(Id(:NOMX), _("Suppress MX Lookups"), _NOMX))
      )

      if _ACTION == "edit"
        Builtins.foreach(_Transports) do |_Transport|
          _TransportID = Ops.get_string(_Transport, "Destination", "")
          if _CID == _TransportID
            _Protocol = Ops.get_string(_Transport, "Transport", "")
            if !Builtins.contains(_Protocols, _Protocol)
              _Protocols = Builtins.add(_Protocols, _Protocol)
            end
            _Destination = Ops.get_string(_Transport, "Destination", "")
            if Builtins.search(Ops.get_string(_Transport, "Nexthop", ""), "[") != nil
              _Server = Builtins.deletechars(
                Ops.get_string(_Transport, "Nexthop", ""),
                "["
              )
              _Server = Builtins.deletechars(_Server, "]")
            else
              _Server = Ops.get_string(_Transport, "Nexthop", "")
              _NOMX = false
            end
            _TLS = Ops.get(_TLSSites, _Server, "NONE")
            if _TLS == "NONE"
              _TransportTLSnone = true
              _TransportTLSuse = false
              _TransportTLSenforce = false
            elsif _TLS == "MUST"
              _TransportTLSnone = false
              _TransportTLSuse = false
              _TransportTLSenforce = true
            end
            if Ops.get(_SASLAccounts, _Server, []) != []
              _Auth = true
              _Account = Ops.get_string(_SASLAccounts, [_Server, 0], "")
              _Password = Ops.get_string(_SASLAccounts, [_Server, 1], "")
            end
          end
        end
        return if _Destination == ""
        main = VBox(
          Left(TextEntry(Id(:Destination), _("Destination"), _Destination)),
          Left(
            ComboBox(
              Id(:Protocol),
              Opt(:editable),
              _("Transport"),
              MakeSelectedList(_Protocols, _Protocol)
            )
          ),
          Left(TextEntry(Id(:Server), _("Server"), _Server)),
          Left(CheckBox(Id(:NOMX), _("Suppress MX Lookups"), _NOMX))
        )
      end
      _TransportAuth = VBox(
        Left(
          CheckBox(
            Id(:Auth),
            Opt(:notify),
            _("Server Requires Authentication"),
            true
          )
        ),
        Left(TextEntry(Id(:Account), _("Account"), _Account)),
        Left(term(:Password, Id(:Password1), _("Password"), _Password)),
        Left(term(:Password, Id(:Password2), _("Confirm Password"), _Password))
      )
      if !_Auth
        _TransportAuth = VBox(
          Left(
            CheckBox(
              Id(:Auth),
              Opt(:notify),
              _("Server Requires Authentication"),
              false
            )
          ),
          Left(TextEntry(Id(:Account), Opt(:disabled), _("Account"), _Account)),
          Left(
            term(
              :Password,
              Id(:Password1),
              Opt(:disabled),
              _("Password"),
              _Password
            )
          ),
          Left(
            term(
              :Password,
              Id(:Password2),
              Opt(:disabled),
              _("Confirm Password"),
              _Password
            )
          )
        )
      end
      UI.OpenDialog(
        Opt(:decorated),
        VBox(
          Frame(
            _("Manage Mail Routing"),
            HBox(
              main,
              Frame(
                _("Security"),
                VBox(
                  Left(Label(_("TLS Mode:"))),
                  RadioButtonGroup(
                    Id(:TLS),
                    HBox(
                      Left(RadioButton(Id("NONE"), _("No"), _TransportTLSnone)),
                      Left(RadioButton(Id("MAY"), _("Use"), _TransportTLSuse)),
                      Left(
                        RadioButton(
                          Id("MUST"),
                          _("Enforce"),
                          _TransportTLSenforce
                        )
                      )
                    )
                  ),
                  _TransportAuth
                )
              )
            )
          ),
          ButtonBox(
            PushButton(Id(:cancel), _("Cancel")),
            PushButton(Id(:ok), _("OK"))
          )
        )
      )

      ret = nil
      _SenderRestriction = {}
      while true
        event = UI.WaitForEvent
        ret = Ops.get(event, "ID")
        break if ret == :cancel

        if ret == :Auth
          if Convert.to_boolean(UI.QueryWidget(Id(:Auth), :Value))
            UI.ChangeWidget(Id(:Account), :Enabled, true)
            UI.ChangeWidget(Id(:Password1), :Enabled, true)
            UI.ChangeWidget(Id(:Password2), :Enabled, true)
          else
            UI.ChangeWidget(Id(:Account), :Enabled, false)
            UI.ChangeWidget(Id(:Password1), :Enabled, false)
            UI.ChangeWidget(Id(:Password2), :Enabled, false)
          end
          next
        end
        Ops.set(MailServer.MailTransports, "Changed", true)
        _Transports2 = Ops.get_list(MailServer.MailTransports, "Transports", [])

        #Now we generate the new/edited entry
        password1 = ""
        password2 = ""
        _Account2 = ""
        _NewTransport = {}
        _NewTLSSite = ""
        _NewTLS = ""
        Ops.set(
          _NewTransport,
          "Destination",
          Convert.to_string(UI.QueryWidget(Id(:Destination), :Value))
        )
        Ops.set(
          _NewTransport,
          "Transport",
          Convert.to_string(UI.QueryWidget(Id(:Protocol), :Value))
        )
        Ops.set(
          _NewTransport,
          "Nexthop",
          Convert.to_string(UI.QueryWidget(Id(:Server), :Value))
        )
        # Now we looking for if everything is all right
        if !Builtins.regexpmatch(
            Ops.get_string(_NewTransport, "Destination", ""),
            "^[+@0-9a-zA-Z.*-]*$"
          ) ||
            Ops.get_string(_NewTransport, "Destination", "") == ""
          Report.Error(_("The destination is invalid."))
          next
        end
        if !Builtins.regexpmatch(
            Ops.get_string(_NewTransport, "Nexthop", ""),
            "^[0-9a-zA-Z.-]*$"
          ) ||
            Ops.get_string(_NewTransport, "Nexthop", "") == ""
          Report.Error(_("The server is invalid."))
          next
        end
        if Ops.get_string(_NewTransport, "Transport", "smtp") != "error"
          _NewTLSSite = Convert.to_string(UI.QueryWidget(Id(:Server), :Value))
          _NewTLS = Convert.to_string(UI.QueryWidget(Id(:TLS), :CurrentButton))
          if Convert.to_boolean(UI.QueryWidget(Id(:Auth), :Value))
            password1 = Convert.to_string(
              UI.QueryWidget(Id(:Password1), :Value)
            )
            password2 = Convert.to_string(
              UI.QueryWidget(Id(:Password2), :Value)
            )
            _Account2 = Convert.to_string(UI.QueryWidget(Id(:Account), :Value))
          end
          if Convert.to_boolean(UI.QueryWidget(Id(:NOMX), :Value))
            Ops.set(
              _NewTransport,
              "Nexthop",
              Ops.add(
                Ops.add("[", Ops.get_string(_NewTransport, "Nexthop", "")),
                "]"
              )
            )
          end
        end

        if _ACTION == "add"
          _TR = []
          Builtins.foreach(_Transports2) do |_Transport|
            _TR = Builtins.add(
              _TR,
              Ops.get_string(_Transport, "Destination", "")
            )
          end
          #TODO search for .<domainname to>
          if Builtins.contains(
              _TR,
              Ops.get_string(_NewTransport, "Destination", "")
            )
            Report.Error(
              _("There is already a transport defined for this destination.")
            )
            next
          end
        end
        if _ACTION == "edit"
          # modify
          if Convert.to_boolean(UI.QueryWidget(Id(:Auth), :Value))
            if password1 != password2
              Report.Error(_("The passwords are not identical."))
              next
            end
          end
          Ops.set(MailServer.MailTransports, "Transports", [])
          Builtins.foreach(_Transports2) do |_Transport|
            if Ops.get_string(_Transport, "Destination", "") == _CID
              Ops.set(
                MailServer.MailTransports,
                "Transports",
                Builtins.add(
                  Ops.get_list(MailServer.MailTransports, "Transports", []),
                  _NewTransport
                )
              )
            else
              Ops.set(
                MailServer.MailTransports,
                "Transports",
                Builtins.add(
                  Ops.get_list(MailServer.MailTransports, "Transports", []),
                  _Transport
                )
              )
            end
          end
          _CID = Ops.get_string(_NewTransport, "Destination", "")
          if _NewTLSSite != "" && _NewTLS != ""
            Ops.set(_TLSSites, _NewTLSSite, _NewTLS)
            Ops.set(MailServer.MailTransports, "TLSSites", _TLSSites)
          end
          if _Account2 != ""
            Ops.set(_SASLAccounts, _NewTLSSite, [_Account2, password1])
            Ops.set(MailServer.MailTransports, "SASLAccounts", _SASLAccounts)
          end
        else
          # add
          if Convert.to_boolean(UI.QueryWidget(Id(:Auth), :Value))
            if password1 != password2
              Report.Error(_("The passwords are not identical."))
              next
            end
          end
          Ops.set(
            MailServer.MailTransports,
            "Transports",
            Builtins.add(
              Ops.get_list(MailServer.MailTransports, "Transports", []),
              _NewTransport
            )
          )
          if Convert.to_boolean(UI.QueryWidget(Id(:Subdomains), :Value))
            Ops.set(
              _NewTransport,
              "Destination",
              Ops.add(".", Ops.get_string(_NewTransport, "Destination", ""))
            )
            Ops.set(
              MailServer.MailTransports,
              "Transports",
              Builtins.add(
                Ops.get_list(MailServer.MailTransports, "Transports", []),
                _NewTransport
              )
            )
          end
          _CID = Ops.get_string(_NewTransport, "Destination", "")
          if _NewTLSSite != "" && _NewTLS != "" &&
              Ops.get(_TLSSites, _NewTLSSite, "") == ""
            Ops.set(_TLSSites, _NewTLSSite, _NewTLS)
            Ops.set(MailServer.MailTransports, "TLSSites", _TLSSites)
          end
          if _Account2 != ""
            Ops.set(_SASLAccounts, _NewTLSSite, [_Account2, password1])
            Ops.set(MailServer.MailTransports, "SASLAccounts", _SASLAccounts)
          end
        end
        break
      end
      UI.CloseDialog
      nil
    end

    def MailTransportsDialog
      Builtins.y2milestone("--Start MailTransportsDialog ---")
      _Transports = Ops.get_list(MailServer.MailTransports, "Transports", [])
      _TLSSites = Ops.get_map(MailServer.MailTransports, "TLSSites", {})
      _Transport_items = []
      _TransportID = ""
      _Server = ""
      _TLS = ""

      Builtins.foreach(_Transports) do |_Transport|
        _TransportID = Ops.get_string(_Transport, "Destination", "")
        if Builtins.search(Ops.get_string(_Transport, "Nexthop", ""), "[") != nil
          _Server = Builtins.deletechars(
            Ops.get_string(_Transport, "Nexthop", ""),
            "["
          )
          _Server = Builtins.deletechars(_Server, "]")
        else
          _Server = Ops.get_string(_Transport, "Nexthop", "")
        end
        _TLS = Ops.get(_TLSSites, _Server, "NONE")
        my_item = Item(
          Id(_TransportID),
          Ops.get_string(_Transport, "Destination", ""),
          Ops.get_string(_Transport, "Nexthop", ""),
          Ops.get_string(_Transport, "Transport", ""),
          _TLS
        )
        _Transport_items = Builtins.add(_Transport_items, my_item)
      end

      content = VBox(
        Left(Label(_("Defined Mail Transport Route"))),
        HBox(
          HWeight(
            22,
            Table(
              Id(:table),
              Opt(:immediate, :keepSorting, :notify),
              Header(
                _("Destination"),
                _("Server"),
                _("Transport"),
                _("Security")
              ),
              _Transport_items
            )
          ),
          HWeight(
            6,
            Top(
              VBox(
                HBox(HWeight(1, PushButton(Id(:Add), _("Add")))),
                HBox(HWeight(1, PushButton(Id(:Edit), _("Change")))),
                HBox(HWeight(1, PushButton(Id(:Delete), _("Delete"))))
              )
            )
          )
        ),
        Left(
          CheckBox(
            Id(:Use),
            Opt(:notify),
            _("&Use Defined Mail Transport Route"),
            Ops.get_boolean(MailServer.MailTransports, "Use", true)
          )
        )
      )
      deep_copy(content)
    end

    def MailPreventionDialog(_CID, _CIDRBL)
      Builtins.y2milestone("--Start MailPreventionDialog ---")
      _AccessItems = []
      _RBLItems = []
      _BasicProtection = Ops.get_string(
        MailServer.MailPrevention,
        "BasicProtection",
        ""
      )
      _RBLList = Ops.get_list(MailServer.MailPrevention, "RBLList", [])
      _AccessList = Ops.get_list(MailServer.MailPrevention, "AccessList", [])
      _VirusScanning = Ops.get_boolean(
        MailServer.MailPrevention,
        "VirusScanning",
        false
      )
      _SpamLearning = Ops.get_boolean(
        MailServer.MailPrevention,
        "SpamLearning",
        false
      )
      _VSCount = Ops.get_integer(MailServer.MailPrevention, "VSCount", 5)
      _BasicProtectionOff = false
      _BasicProtectionMedium = false
      _BasicProtectionHard = true

      Builtins.y2milestone("---- VSCount %1", _VSCount)

      if _BasicProtection == "off"
        _BasicProtectionOff = true
        _BasicProtectionHard = false
      elsif _BasicProtection == "medium"
        _BasicProtectionMedium = true
        _BasicProtectionHard = false
      end

      Builtins.foreach(_AccessList) do |_Access|
        my_item = Item(
          Id(Ops.get(_Access, "MailClient", "")),
          Ops.get(_Access, "MailClient", ""),
          Ops.get(
            Builtins.splitstring(Ops.get(_Access, "MailAction", ""), " "),
            0,
            ""
          ),
          Builtins.substring(
            Ops.get(_Access, "MailAction", ""),
            Builtins.search(Ops.get(_Access, "MailAction", ""), " ")
          )
        )
        _AccessItems = Builtins.add(_AccessItems, my_item)
      end

      Builtins.foreach(_RBLList) do |_RBLServer|
        my_item = Item(Id(_RBLServer), _RBLServer)
        _RBLItems = Builtins.add(_RBLItems, my_item)
      end

      _SpamL = Left(
        CheckBox(
          Id(:SpamLearning),
          Opt(:disabled),
          _("Configure Spam Learning Extension"),
          false
        )
      )
      if Ops.get_string(MailServer.MailLocalDelivery, "Type", "") == "imap"
        _SpamL = Left(
          CheckBox(
            Id(:SpamLearning),
            Opt(:notify),
            _("Configure Spam Learning Extension"),
            _SpamLearning
          )
        )
      end
      content = VBox(
        Left(
          CheckBox(
            Id(:VirusScanning),
            Opt(:notify),
            _("Start Virus Scanner AMAVIS"),
            _VirusScanning
          )
        ),
        VSpacing(1),
        Left(
          IntField(
            Id(:VSCount),
            Opt(:notify),
            _("Count of Virus Scanner Process"),
            1,
            50,
            _VSCount
          )
        ),
        VSpacing(1),
        _SpamL,
        VSpacing(1),
        Frame(
          _("SPAM Prevention"),
          HBox(
            HWeight(
              7,
              Top(
                RadioButtonGroup(
                  Id(:BasicProtection),
                  VBox(
                    Left(Label(_("Basic Settings:"))),
                    Left(
                      RadioButton(
                        Id("off"),
                        Opt(:notify),
                        _("Off"),
                        _BasicProtectionOff
                      )
                    ),
                    Left(
                      RadioButton(
                        Id("medium"),
                        Opt(:notify),
                        _("Medium"),
                        _BasicProtectionMedium
                      )
                    ),
                    Left(
                      RadioButton(
                        Id("hard"),
                        Opt(:notify),
                        _("Hard"),
                        _BasicProtectionHard
                      )
                    )
                  )
                )
              )
            ),
            HWeight(
              13,
              Top(
                VBox(
                  SelectionBox(
                    Id(:RBLList),
                    _("Configured RBL Server"),
                    _RBLItems
                  )
                )
              )
            ),
            HWeight(
              6,
              Top(
                VBox(
                  Label(""),
                  PushButton(Id(:RBLAdd), _("Add")),
                  PushButton(Id(:RBLDelete), _("Delete"))
                )
              )
            )
          )
        ),
        Left(Label(_("Sender Restrictions"))),
        HBox(
          HWeight(
            20,
            Table(
              Id(:table),
              Opt(:immediate, :keepSorting, :notify),
              Header(_("Sender Address"), _("Action"), _("Option")),
              _AccessItems
            )
          ),
          HWeight(
            6,
            Top(
              VBox(
                PushButton(Id(:AccessAdd), _("Add")),
                PushButton(Id(:AccessDelete), _("Delete"))
              )
            )
          )
        )
      )
      deep_copy(content)
    end

    def RBLAdd
      UI.OpenDialog(
        Opt(:decorated),
        Frame(
          _("Add New RBL Server"),
          VBox(
            TextEntry(Id(:server), "", ""),
            ButtonBox(
              PushButton(Id(:cancel), _("Cancel")),
              PushButton(Id(:ok), _("OK"))
            )
          )
        )
      )
      ret = nil
      server = ""
      while ret != :cancel && ret != :ok
        event = UI.WaitForEvent
        ret = Ops.get(event, "ID")
        if ret == :ok
          server = Convert.to_string(UI.QueryWidget(Id(:server), :Value))
        end
      end
      UI.CloseDialog
      server
    end

    def AccessAdd
      UI.OpenDialog(
        Opt(:decorated),
        Frame(
          _("Add New Sender Restriction"),
          VBox(
            TextEntry(Id(:NewSender), _("Sender Address"), ""),
            ComboBox(
              Id(:NewSenderAction),
              _("Action"),
              [
                "REJECT",
                "DEFER_IF_REJECT",
                "DEFER_IF_PERMIT",
                "OK",
                "DUNNO",
                "PREPEND",
                "HOLD",
                "DISCARD",
                "FILTER",
                "REDIRECT",
                ""
              ]
            ),
            TextEntry(Id(:NewSenderOption), _("Option"), ""),
            ButtonBox(
              PushButton(Id(:cancel), _("Cancel")),
              PushButton(Id(:ok), _("OK"))
            )
          )
        )
      )
      ret = nil
      _SenderRestriction = {}
      while ret != :cancel && ret != :ok
        event = UI.WaitForEvent
        ret = Ops.get(event, "ID")
        if ret == :ok
          _NewSender = Convert.to_string(UI.QueryWidget(Id(:NewSender), :Value))
          _NewSenderAction = Convert.to_string(
            UI.QueryWidget(Id(:NewSenderAction), :Value)
          )
          _NewSenderOption = Convert.to_string(
            UI.QueryWidget(Id(:NewSenderOption), :Value)
          )
          _SenderRestriction = {
            "MailClient" => _NewSender,
            "MailAction" => Ops.add(
              Ops.add(_NewSenderAction, " "),
              _NewSenderOption
            )
          }
        end
      end
      UI.CloseDialog
      deep_copy(_SenderRestriction)
    end

    def MailRelayingDialog
      Builtins.y2milestone("--Start MailRelayingDialog ---")
      #  boolean UserRestriction = ((string)MailServer::MailRelaying["UserRestriction"]:"0" == "1");
      _RequireSASL = Ops.get_string(MailServer.MailRelaying, "RequireSASL", "0") == "1"
      _SMTPDTLSnone = Ops.get_string(
        MailServer.MailRelaying,
        "SMTPDTLSMode",
        "none"
      ) == "none"
      _SMTPDTLSuse = Ops.get_string(
        MailServer.MailRelaying,
        "SMTPDTLSMode",
        "none"
      ) == "use"
      _SMTPDTLSenforce = Ops.get_string(
        MailServer.MailRelaying,
        "SMTPDTLSMode",
        "none"
      ) == "enforce"
      _SMTPDTLSauth_only = Ops.get_string(
        MailServer.MailRelaying,
        "SMTPDTLSMode",
        "none"
      ) == "auth_only"
      _Networks = Ops.get_list(MailServer.MailRelaying, "TrustedNetworks", [])
      _Network_items = []
      _NetworkID = 1

      Builtins.foreach(_Networks) do |_Network|
        my_item = Item(Id(_NetworkID), _Network)
        _Network_items = Builtins.add(_Network_items, my_item)
        _NetworkID = Ops.add(_NetworkID, 1)
      end

      security = HBox(
        Top(
          VBox(
            Label(""),
            Left(
              CheckBox(
                Id(:RequireSASL),
                _("Require SASL Authentication"),
                _RequireSASL
              )
            )
          )
        ),
        RadioButtonGroup(
          Id(:SMTPDTLSMode),
          VBox(
            Left(Label(_("TLS Mode for the SMTPD Daemon"))),
            Left(RadioButton(Id("none"), _("No TLS"), _SMTPDTLSnone)),
            Left(RadioButton(Id("use"), _("Use TLS"), _SMTPDTLSuse)),
            Left(RadioButton(Id("enforce"), _("Enforce TLS"), _SMTPDTLSenforce)),
            Left(
              RadioButton(
                Id("auth_only"),
                _("Use TLS Only for SASL Authentication"),
                _SMTPDTLSauth_only
              )
            )
          )
        )
      )

      content = VBox(
        Frame(
          _("Trusted Local Networks"),
          VBox(
            HBox(
              TextEntry(Id(:NewNetwork), _("New Network"), ""),
              PushButton(Id(:AddNewNetwork), _("Add"))
            ),
            HBox(
              SelectionBox(
                Id(:TrustedNetworks),
                _("Defined Trusted Networks"),
                _Networks
              ),
              Top(VBox(Label(""), PushButton(Id(:DeleteNetwork), _("Delete"))))
            )
          )
        ),
        Frame(_("Security Settings for Sending Mail via the Server"), security)
      )
      deep_copy(content)
    end

    def MailLocalDeliveryDialog
      Builtins.y2milestone("--Start MailLocalDeliveryDialog ---")
      _TypeIMAP = Ops.get_string(MailServer.MailLocalDelivery, "Type", "") == "imap"
      _TypePROCMAIL = Ops.get_string(MailServer.MailLocalDelivery, "Type", "") == "procmail"
      _TypeLOCAL = Ops.get_string(MailServer.MailLocalDelivery, "Type", "") == "local"
      _TypeNONE = Ops.get_string(MailServer.MailLocalDelivery, "Type", "") == "none"
      limit = Ops.get_string(
        MailServer.MailLocalDelivery,
        "MailboxSizeLimit",
        "0"
      ) != "0"
      _MMS = Builtins.tointeger(
        Ops.get_string(MailServer.MailLocalDelivery, "MailboxSizeLimit", "0")
      )


      settings = HBox()
      if _TypeIMAP
        _QuotaLimit = Builtins.tointeger(
          Ops.get_string(MailServer.MailLocalDelivery, "QuotaLimit", "0")
        )
        _ImapIdleTime = Builtins.tointeger(
          Ops.get_string(MailServer.MailLocalDelivery, "ImapIdleTime", "0")
        )
        _PopIdleTime = Builtins.tointeger(
          Ops.get_string(MailServer.MailLocalDelivery, "PopIdleTime", "0")
        )
        _MAXINT = 10000000000000
        _HardQuotaLimit = Ops.get_string(
          MailServer.MailLocalDelivery,
          "HardQuotaLimit",
          "0"
        ) == "1"
        _AlternateNameSpace = Ops.get_string(
          MailServer.MailLocalDelivery,
          "AlternateNameSpace",
          "0"
        ) == "1"
        _FallBackMailbox = Ops.get_string(
          MailServer.MailLocalDelivery,
          "FallBackMailbox",
          "root"
        )
        _ImapSecurity = Ops.get_string(
          MailServer.MailLocalDelivery,
          "Security",
          "0"
        ) == "1"
        settings = Frame(
          _("IMAP Settings"),
          VBox(
            HBox(
              Label(" "),
              Frame(
                _("Security (SSL and TLS)"),
                HBox(
                  Left(CheckBox(Id(:ImapSecurity), _("Enabled"), _ImapSecurity))
                )
              )
            ),
            HBox(
              Label(" "),
              HWeight(
                1,
                VBox(
                  Left(
                    IntField(
                      Id(:MailboxSizeLimit),
                      _("Default Mailbox Size (KB)"),
                      0,
                      _MAXINT,
                      _MMS
                    )
                  ),
                  Left(
                    IntField(
                      Id(:QuotaLimit),
                      _("Quota Warning Limit (%)"),
                      0,
                      100,
                      _QuotaLimit
                    )
                  )
                )
              ),
              HWeight(
                1,
                VBox(
                  Left(
                    IntField(
                      Id(:ImapIdleTime),
                      _("IMAP Idle Time (Min)"),
                      30,
                      100,
                      _ImapIdleTime
                    )
                  ),
                  Left(
                    IntField(
                      Id(:PopIdleTime),
                      _("POP Idle Time (Min)"),
                      10,
                      100,
                      _PopIdleTime
                    )
                  )
                )
              )
            ),
            HBox(
              Label(" "),
              VBox(
                Left(
                  CheckBox(
                    Id(:HardQuotaLimit),
                    _("Hard Quota Limit"),
                    _HardQuotaLimit
                  )
                ),
                Left(
                  CheckBox(
                    Id(:AlternateNameSpace),
                    _("Use Alternate Name Space"),
                    _AlternateNameSpace
                  )
                )
              ),
              TextEntry(
                Id(:FallBackMailbox),
                _("Fallback Mailbox"),
                _FallBackMailbox
              )
            )
          )
        )
      elsif _TypeLOCAL
        _SpoolDirectory = Ops.get_string(
          MailServer.MailLocalDelivery,
          "SpoolDirectory",
          ""
        )
        mdir = Builtins.regexpmatch(_SpoolDirectory, "/$")
        varspool = Builtins.regexpmatch(_SpoolDirectory, "var")
        homedir = Builtins.regexpmatch(_SpoolDirectory, "HOME/Mail")
        #    boolean custom   = (regexpmatch(SpoolDirectory,"HOME") && !homedir);
        _MailboxSizeTerm = TextEntry(
          Id(:MailboxSizeLimit),
          "",
          Builtins.sformat("%1", _MMS)
        )
        if !limit
          _MailboxSizeTerm = TextEntry(
            Id(:MailboxSizeLimit),
            Opt(:disabled),
            "",
            "0"
          )
        end

        settings = Frame(
          _("Settings for File System Delivery"),
          VBox(
            HBox(
              Label(" "),
              HWeight(
                12,
                Frame(
                  _("Type"),
                  RadioButtonGroup(
                    Id(:MailboxType),
                    VBox(
                      Left(RadioButton(Id("mbox"), _("Mailbox"), !mdir)),
                      Left(RadioButton(Id("mdir"), _("Maildir"), mdir))
                    )
                  )
                )
              ),
              Label(" "),
              HWeight(
                12,
                Frame(
                  _("Repository"),
                  RadioButtonGroup(
                    Id(:Repository),
                    VBox(
                      Left(
                        RadioButton(
                          Id("varspool"),
                          "/var/spool/mail/$USER",
                          varspool
                        )
                      ),
                      Left(RadioButton(Id("homedir"), "$HOME/Mail", homedir))
                    )
                  )
                )
              ),
              Label(" ")
            ),
            Label(" "),
            HBox(
              Label(" "),
              Frame(
                _("Mailbox Size"),
                RadioButtonGroup(
                  Id(:MailboxSize),
                  HBox(
                    RadioButton(
                      Id("NoLimit"),
                      Opt(:notify),
                      _("No Limit"),
                      !limit
                    ),
                    RadioButton(
                      Id("Limit"),
                      Opt(:notify),
                      _("Mailbox Size"),
                      limit
                    ),
                    _MailboxSizeTerm,
                    Label(_("KByte"))
                  )
                )
              ),
              Label(" ")
            ),
            Label(" ")
          )
        )
      elsif _TypePROCMAIL
        settings = Frame(
          _("Settings for Procmail"),
          HBox(
            HStretch(),
            Label(_("There are no settings for procmail.")),
            HStretch()
          )
        )
      end

      content = VBox(
        Frame(
          _("Local Delivery Type"),
          HBox(
            RadioButtonGroup(
              Id(:Type),
              VBox(
                Left(
                  RadioButton(
                    Id("imap"),
                    Opt(:notify),
                    _("IMAP"),
                    _TypeIMAP
                  )
                ),
                Left(
                  RadioButton(
                    Id("procmail"),
                    Opt(:notify),
                    _("Procmail"),
                    _TypePROCMAIL
                  )
                ),
                Left(
                  RadioButton(
                    Id("local"),
                    Opt(:notify),
                    _("File System"),
                    _TypeLOCAL
                  )
                ),
                Left(
                  RadioButton(
                    Id("none"),
                    Opt(:notify),
                    _("No Local Delivery"),
                    _TypeNONE
                  )
                )
              )
            ),
            HStretch()
          )
        ),
        settings,
        VStretch()
      )
      deep_copy(content)
    end

    def FetchingMailDialog
      Builtins.y2milestone("--Start FetchingMailDialog ---")
      table_items = []
      _IID = 0
      entries = Ops.get_list(MailServer.FetchingMail, "Items", [])
      _FetchByDialIn = Ops.get_string(
        MailServer.FetchingMail,
        "FetchByDialIn",
        ""
      ) == "1"
      _FetchMailSteady = Ops.get_string(
        MailServer.FetchingMail,
        "FetchMailSteady",
        ""
      ) == "1"
      _FetchingInterval = Builtins.tointeger(
        Ops.get_string(MailServer.FetchingMail, "FetchingInterval", "")
      )
      _NoLocalDelivery = Ops.get_string(
        MailServer.MailLocalDelivery,
        "Type",
        ""
      ) == "none"

      if _NoLocalDelivery
        Ops.set(MailServer.FetchingMail, "FetchByDialIn", 0)
        Ops.set(MailServer.FetchingMail, "FetchMailSteady", 0)
        return Frame(
          "",
          VBox(
            Label(_("There is no local mail delivery defined.")),
            Label(_("You cannot define mail fetching jobs."))
          )
        )
      end

      Builtins.foreach(entries) do |entry|
        item = Item(
          Id(_IID),
          Ops.get(entry, "server", ""),
          Ops.get(entry, "protocol", ""),
          Ops.get(entry, "remote_user", ""),
          Ops.get(entry, "local_user", "")
        )
        table_items = Builtins.add(table_items, item)
        _IID = Ops.add(_IID, 1)
      end

      _FetchingIntervalTerm = HBox(
        CheckBox(
          Id(:FetchMailSteady),
          Opt(:notify),
          _("Fetch Mail Regularly"),
          _FetchMailSteady
        ),
        Label(_("Fetching Interval")),
        IntField(Id(:FetchingInterval), _("Min"), 10, 120, _FetchingInterval),
        HStretch()
      )
      if !_FetchMailSteady
        _FetchingIntervalTerm = HBox(
          CheckBox(
            Id(:FetchMailSteady),
            Opt(:notify),
            _("Fetch Mail Regularly"),
            _FetchMailSteady
          ),
          Label(Opt(:disabled), _("Fetching Interval")),
          IntField(
            Id(:FetchingInterval),
            Opt(:disabled),
            _("Min"),
            5,
            120,
            _FetchingInterval
          ),
          HStretch()
        )
      end
      _Scheduler = nil


      if Builtins.size(MailServer.PPPCards) == 1
        _Scheduler = VBox(
          Left(
            CheckBox(
              Id(:FetchByDialIn),
              Opt(:notify),
              _("Fetch Mail by Connecting to Internet"),
              _FetchByDialIn
            )
          ),
          Left(_FetchingIntervalTerm)
        )
      elsif Ops.greater_than(Builtins.size(MailServer.PPPCards), 1)
        _Scheduler = VBox(
          HBox(
            Left(
              CheckBox(
                Id(:FetchByDialIn),
                Opt(:notify),
                _("Fetch Mail by Connecting to Internet"),
                _FetchByDialIn
              )
            ),
            Left(
              ComboBox(
                Id(:Interface),
                _("Choose the Internet interface."),
                MakeSelectedList(
                  MailServer.PPPCards,
                  Ops.get_string(MailServer.FetchingMail, "Interface", "")
                )
              )
            )
          ),
          Left(_FetchingIntervalTerm)
        )
      else
        _Scheduler = VBox(Left(_FetchingIntervalTerm))
      end

      content = VBox(
        Frame(_("Mail Fetching Scheduler"), _Scheduler),
        HBox(
          VBox(
            Left(Label(_("Defined  Fetchmail Jobs"))),
            Table(
              Id(:table),
              Opt(:keepSorting),
              Header(_("Server"), _("Protocol"), _("User"), _("Local User")),
              table_items
            )
          ),
          Top(
            VBox(
              Label(""),
              PushButton(Id(:Add), _("Add")),
              #	         `PushButton(`id(`Edit),  _("Edit")),
              PushButton(Id(:Delete), _("Delete"))
            )
          )
        )
      )
      deep_copy(content)
    end

    def FetchmailAddItem
      Builtins.y2milestone("--Start FetchmailAddItem ---")
      UI.OpenDialog(
        Opt(:decorated),
        Frame(
          _("Add New Fetchmail Job"),
          VBox(
            TextEntry(Id(:server), _("Server Address"), ""),
            ComboBox(
              Id(:protocol),
              _("Protocol"),
              [
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
            ),
            TextEntry(Id(:remote_user), _("Remote User"), ""),
            Password(Id(:password), Label.Password, ""),
            Password(Id(:cpassword), Label.ConfirmPassword, ""),
            TextEntry(Id(:local_user), _("Local User"), ""),
            ButtonBox(
              PushButton(Id(:cancel), _("Cancel")),
              PushButton(Id(:ok), _("OK"))
            )
          )
        )
      )
      ret = nil
      _Job = {}
      while ret != :cancel && ret != :ok
        event = UI.WaitForEvent
        ret = Ops.get(event, "ID")
        if ret == :ok
          # --------------------------------- password checks
          pw1 = Convert.to_string(UI.QueryWidget(Id(:password), :Value))
          pw2 = Convert.to_string(UI.QueryWidget(Id(:cpassword), :Value))

          if pw1 != pw2
            # The two user password information do not match
            # error popup
            Report.Error(_("The passwords do not match.\nTry again."))
            UI.SetFocus(Id(:password))
            ret = nil
            next
          end

          Ops.set(_Job, "server", UI.QueryWidget(Id(:server), :Value))
          Ops.set(_Job, "protocol", UI.QueryWidget(Id(:protocol), :Value))
          Ops.set(_Job, "remote_user", UI.QueryWidget(Id(:remote_user), :Value))
          Ops.set(_Job, "password", UI.QueryWidget(Id(:password), :Value))
          Ops.set(_Job, "local_user", UI.QueryWidget(Id(:local_user), :Value))
          Ops.set(_Job, "other_server_options", "")
          Ops.set(_Job, "other_user_options", "")
          Ops.set(_Job, "enabled", true)
        end
      end
      UI.CloseDialog
      deep_copy(_Job)
    end

    def MailLocalDomainsDialog(_CID)
      Builtins.y2milestone("--Start MailLocalDomainsDialog ---")
      _Domains = []
      _NoLocalDelivery = Ops.get_string(
        MailServer.MailLocalDelivery,
        "Type",
        ""
      ) == "none"
      if _NoLocalDelivery
        return Frame(
          "",
          VBox(
            Label(_("There is no local mail delivery defined.")),
            Label(_("You cannot define local domains for the mail server."))
          )
        )
      end

      _Name = ""
      _Type = "none"
      _Masquerading = false
      _Types = ["main", "virtual", "local", "none"]

      Builtins.foreach(Ops.get_list(MailServer.MailLocalDomains, "Domains", [])) do |_Domain|
        _Domains = Builtins.add(
          _Domains,
          Item(
            Id(Ops.get_string(_Domain, "Name", "")),
            Ops.get_string(_Domain, "Name", ""),
            Ops.get_string(_Domain, "Type", ""),
            Ops.get_string(_Domain, "Masquerading", "")
          )
        )
        if _CID == Ops.get_string(_Domain, "Name", "")
          _Name = Ops.get_string(_Domain, "Name", "")
          _Type = Ops.get_string(_Domain, "Type", "")
          _Masquerading = Ops.get_string(_Domain, "Masquerading", "") == "yes"
        end
      end
      if _Name == "" &&
          Ops.greater_than(
            Builtins.size(
              Ops.get_list(MailServer.MailLocalDomains, "Domains", [])
            ),
            0
          )
        _Domain = Ops.get(
          Ops.get_list(MailServer.MailLocalDomains, "Domains", []),
          0,
          {}
        )
        _Name = Ops.get_string(_Domain, "Name", "")
        _Type = Ops.get_string(_Domain, "Type", "")
        _Masquerading = Ops.get_string(_Domain, "Masquerading", "") == "yes"
      end

      content = VBox(
        Left(Label(_("Defined Domains"))),
        HBox(
          Table(
            Id(:table),
            Opt(:immediate, :keepSorting, :notify),
            Header(_("Domain"), _("Type"), _("Masquerading")),
            _Domains
          ),
          Top(
            VBox(
              PushButton(Id(:Add), _("Add")),
              PushButton(Id(:Change), _("Change")),
              PushButton(Id(:Delete), _("Delete"))
            )
          )
        )
      )
      deep_copy(content)
    end

    def ShowMailLocalDomain(_CID, _ACTION)
      Builtins.y2milestone("--Start ShowMailLocalDomain ---")
      _Name = ""
      _Type = "local"
      _Masquerading = true
      _Types = ["main", "virtual", "local", "none"]

      if _ACTION == "change"
        Builtins.foreach(
          Ops.get_list(MailServer.MailLocalDomains, "Domains", [])
        ) do |_Domain|
          if _CID == Ops.get_string(_Domain, "Name", "")
            _Name = Ops.get_string(_Domain, "Name", "")
            _Type = Ops.get_string(_Domain, "Type", "")
            _Masquerading = Ops.get_string(_Domain, "Masquerading", "") == "yes"
          end
        end
      end

      # Create the dialog
      UI.OpenDialog(
        Opt(:decorated),
        Frame(
          _("Configure Mail Domains"),
          VBox(
            Left(TextEntry(Id(:Name), _("Name"), _Name)),
            VStretch(),
            Left(
              ComboBox(Id(:Type), _("Type"), MakeSelectedList(_Types, _Type))
            ),
            VStretch(),
            Left(CheckBox(Id(:Masquerading), _("Masquerading"), _Masquerading)),
            ButtonBox(
              PushButton(Id(:cancel), _("Cancel")),
              PushButton(Id(:ok), _("OK"))
            )
          )
        )
      )

      #Waiting for response
      ret = nil
      while ret != :cancel && ret != :ok
        event = UI.WaitForEvent
        ret = Ops.get(event, "ID")
        if ret == :ok
          _Name2 = Convert.to_string(UI.QueryWidget(Id(:Name), :Value))
          _Type2 = Convert.to_string(UI.QueryWidget(Id(:Type), :Value))
          _Masquerading2 = "no"
          Ops.set(MailServer.MailLocalDomains, "Changed", true)
          if Convert.to_boolean(UI.QueryWidget(Id(:Masquerading), :Value))
            _Masquerading2 = "yes"
          end
          if _ACTION == "add"
            Ops.set(
              MailServer.MailLocalDomains,
              "Domains",
              Builtins.add(
                Ops.get_list(MailServer.MailLocalDomains, "Domains", []),
                {
                  "Name"         => _Name2,
                  "Type"         => _Type2,
                  "Masquerading" => _Masquerading2
                }
              )
            )
          else
            _Domains = Ops.get_list(MailServer.MailLocalDomains, "Domains", [])
            Ops.set(MailServer.MailLocalDomains, "Domains", [])
            Builtins.foreach(_Domains) do |_Domain|
              if _CID != Ops.get_string(_Domain, "Name", "")
                Ops.set(
                  MailServer.MailLocalDomains,
                  "Domains",
                  Builtins.add(
                    Ops.get_list(MailServer.MailLocalDomains, "Domains", []),
                    _Domain
                  )
                )
              else
                Ops.set(
                  MailServer.MailLocalDomains,
                  "Domains",
                  Builtins.add(
                    Ops.get_list(MailServer.MailLocalDomains, "Domains", []),
                    {
                      "Name"         => _Name2,
                      "Type"         => _Type2,
                      "Masquerading" => _Masquerading2
                    }
                  )
                )
              end
            end
          end
        end
      end
      UI.CloseDialog

      nil
    end

    def CheckMainDomain
      Builtins.y2milestone("--Start CheckMainDomain ---")
      maindomain = 0
      domains = 0

      if Ops.get_string(MailServer.MailLocalDelivery, "Type", "") == "none"
        return true
      end
      Builtins.foreach(Ops.get_list(MailServer.MailLocalDomains, "Domains", [])) do |_Domain|
        if Ops.get_string(_Domain, "Type", "") == "main"
          maindomain = Ops.add(maindomain, 1)
        end
        domains = Ops.add(domains, 1)
      end
      if maindomain == 0
        Report.Warning(
          _("There is no main mail domain defined. Please fix it!")
        )
        Ops.set(MailServer.MailLocalDomains, "Changed", false)
        return false if Ops.greater_than(domains, 0)
      elsif Ops.greater_than(maindomain, 1)
        Report.Warning(
          _("You have defined more then one main mail domain. Please fix it!")
        )
        Ops.set(MailServer.MailLocalDomains, "Changed", false)
        return false
      end
      true
    end

    def ComplexDialog
      Builtins.y2milestone("--Start ComplexDialog ---")
      Wizard.CreateTreeDialog
      _Tree = GenerateTree([], "", MailServer.ModulesTreeContent)
      Wizard.CreateTree(_Tree, _("Mail Server Configuration"))

      helptext = Ops.get_string(@HELPS, "GlobalSettings", "Bla Bla Bla")
      content = GlobalSettingsDialog()
      title = _("Mail Server Global Settings")
      _FocusedContent = "GlobalSettings"

      _CID = "" #CurrentItem
      _CIDRBL = "" #CurrentItem

      Wizard.SetContents(title, content, helptext, true, true)
      Wizard.SetDesktopIcon("mail")
      UI.WizardCommand(term(:SetBackButtonLabel, ""))
      UI.WizardCommand(term(:SetNextButtonLabel, _("OK")))
      Wizard.SelectTreeItem(_FocusedContent)

      ret = nil
      _EventType = nil
      while ret != :next
        focus_changed = false
        _OldFocusedContent = _FocusedContent

        event = UI.WaitForEvent
        ret = Ops.get(event, "ID")
        _EventType = Ops.get(event, "EventType")

        Builtins.y2milestone("event %1", event)
        Builtins.y2milestone("event %1", ret)
        Builtins.y2milestone("FocusedContent %1", _FocusedContent)

        if ret == :cancel || ret == :abort
          if ReallyAbort()
            break
          else
            next
          end
        end
        #If anithing happenend we save the changes into the global maps
        if _FocusedContent == "GlobalSettings"
          Ops.set(MailServer.GlobalSettings, "Changed", true)
          if UI.QueryWidget(Id(:MailSize), :CurrentButton) == "MailSizeLimit"
            _MMS = Ops.multiply(
              Builtins.tointeger(UI.QueryWidget(Id(:MaximumMailSize), :Value)),
              1024
            )
            Ops.set(
              MailServer.GlobalSettings,
              "MaximumMailSize",
              Builtins.sformat("%1", _MMS)
            )
            if UI.QueryWidget(Id(:MaximumMailSize), :Value) == "0"
              Ops.set(MailServer.GlobalSettings, "MaximumMailSize", "1")
            end
          else
            Ops.set(MailServer.GlobalSettings, "MaximumMailSize", "0")
          end
          Ops.set(
            MailServer.GlobalSettings,
            "Banner",
            UI.QueryWidget(Id(:Banner), :Value)
          )
          _SMT = Convert.to_string(
            UI.QueryWidget(Id(:SendingMailType), :CurrentButton)
          )
          _SMT = "NONE" if _SMT == "NOOUT"
          Ops.set(MailServer.GlobalSettings, ["SendingMail", "Type"], _SMT)
          Ops.set(
            MailServer.GlobalSettings,
            ["SendingMail", "TLS"],
            UI.QueryWidget(Id(:SendingMailTLS), :CurrentButton)
          )
          Ops.set(
            MailServer.GlobalSettings,
            ["SendingMail", "RelayHost", "Name"],
            ""
          )
          Ops.set(
            MailServer.GlobalSettings,
            ["SendingMail", "RelayHost", "Auth"],
            "0"
          )
          Ops.set(
            MailServer.GlobalSettings,
            ["SendingMail", "RelayHost", "Account"],
            ""
          )
          Ops.set(
            MailServer.GlobalSettings,
            ["SendingMail", "RelayHost", "Password"],
            ""
          )

          if Ops.get_string(
              MailServer.GlobalSettings,
              ["SendingMail", "Type"],
              "relayhost"
            ) == "relayhost"
            Ops.set(
              MailServer.GlobalSettings,
              ["SendingMail", "RelayHost", "Name"],
              UI.QueryWidget(Id(:RelayHostName), :Value)
            )
            if Convert.to_boolean(UI.QueryWidget(Id(:RelayHostAuth), :Value))
              password1 = Convert.to_string(
                UI.QueryWidget(Id(:Password1), :Value)
              )
              password2 = Convert.to_string(
                UI.QueryWidget(Id(:Password2), :Value)
              )
              if password1 != password2
                Report.Error(_("The passwords are not identical."))
                next
              end
              Ops.set(
                MailServer.GlobalSettings,
                ["SendingMail", "RelayHost", "Auth"],
                "1"
              )
              Ops.set(
                MailServer.GlobalSettings,
                ["SendingMail", "RelayHost", "Account"],
                UI.QueryWidget(Id(:RelayHostAccount), :Value)
              )
              Ops.set(
                MailServer.GlobalSettings,
                ["SendingMail", "RelayHost", "Password"],
                password1
              )
            end
          end
          title = _("Mail Server Global Settings")
          content = GlobalSettingsDialog()
          helptext = Ops.get_string(@HELPS, "GlobalSettings", "Bla Bla Bla")
        elsif _FocusedContent == "MailTransports"
          _CID = Convert.to_string(UI.QueryWidget(Id(:table), :CurrentItem))
          if ret == :Use
            Ops.set(
              MailServer.MailTransports,
              "Use",
              Convert.to_boolean(UI.QueryWidget(Id(:Use), :Value))
            )
            Ops.set(MailServer.MailTransports, "Changed", true)
            next
          elsif ret == :Add
            ShowMailTransport(_CID, "add")
          elsif ret == :Edit
            ShowMailTransport(_CID, "edit")
          elsif ret == :Delete
            Ops.set(MailServer.MailTransports, "Changed", true)
            _Transports = Ops.get_list(
              MailServer.MailTransports,
              "Transports",
              []
            )
            Ops.set(MailServer.MailTransports, "Transports", [])
            Builtins.foreach(_Transports) do |_Transport|
              if Ops.get_string(_Transport, "Destination", "") != _CID
                #TODO search for .<domainname to>
                Ops.set(
                  MailServer.MailTransports,
                  "Transports",
                  Builtins.add(
                    Ops.get_list(MailServer.MailTransports, "Transports", []),
                    _Transport
                  )
                )
              end
            end
          end
          title = _("Mail Server Transport Configuration")
          content = MailTransportsDialog()
          helptext = Ops.get_string(@HELPS, "MailTransports", "Bla Bla Bla")
        elsif _FocusedContent == "MailPrevention"
          if ret == :VSCount || ret == :VirusScanning || ret == "off" ||
              ret == "medium" ||
              ret == "hard"
            Ops.set(MailServer.MailPrevention, "Changed", true)
            next
          end
          if ret == :SpamLearning
            Ops.set(MailServer.MailPrevention, "Changed", true)
            UI.ChangeWidget(Id(:VirusScanning), :Value, true)
            UI.ChangeWidget(
              Id(:VSCount),
              :Value,
              Ops.get_string(MailServer.MailPrevention, "VSCount", "5")
            )
            next
          end
          if ret == :RBLAdd
            _NewRLBServer = RBLAdd()
            if _NewRLBServer != ""
              Ops.set(
                MailServer.MailPrevention,
                "RBLList",
                Builtins.add(
                  Ops.get_list(MailServer.MailPrevention, "RBLList", []),
                  _NewRLBServer
                )
              )
              _CIDRBL = _NewRLBServer
              Ops.set(MailServer.MailPrevention, "Changed", true)
            end
          end
          if ret == :AccessAdd
            _SenderRestriction = AccessAdd()
            if Ops.get_string(_SenderRestriction, "MailClient", "") != "" &&
                Ops.get_string(_SenderRestriction, "MailAction", "") != ""
              Ops.set(
                MailServer.MailPrevention,
                "AccessList",
                Builtins.add(
                  Ops.get_list(MailServer.MailPrevention, "AccessList", []),
                  _SenderRestriction
                )
              )
              Ops.set(MailServer.MailPrevention, "Changed", true)
            end
            _CID = Ops.get_string(_SenderRestriction, "MailClient", "")
          elsif ret == :RBLDelete
            _Server = Convert.to_string(
              UI.QueryWidget(Id(:RBLList), :CurrentItem)
            )
            _RBLList = Ops.get_list(MailServer.MailPrevention, "RBLList", [])
            Ops.set(MailServer.MailPrevention, "RBLList", [])
            Builtins.foreach(_RBLList) do |my_item|
              if my_item != _Server
                Ops.set(
                  MailServer.MailPrevention,
                  "RBLList",
                  Builtins.add(
                    Ops.get_list(MailServer.MailPrevention, "RBLList", []),
                    my_item
                  )
                )
              end
            end
          elsif ret == :AccessDelete
            _Sender = Convert.to_string(
              UI.QueryWidget(Id(:table), :CurrentItem)
            )
            _AccessList = Ops.get_list(
              MailServer.MailPrevention,
              "AccessList",
              []
            )
            Ops.set(MailServer.MailPrevention, "AccessList", [])
            Builtins.foreach(_AccessList) do |my_item|
              if Ops.get(my_item, "MailClient", "") != _Sender
                Ops.set(
                  MailServer.MailPrevention,
                  "AccessList",
                  Builtins.add(
                    Ops.get_list(MailServer.MailPrevention, "AccessList", []),
                    my_item
                  )
                )
              end
            end
          end
          Ops.set(
            MailServer.MailPrevention,
            "BasicProtection",
            Convert.to_string(
              UI.QueryWidget(Id(:BasicProtection), :CurrentButton)
            )
          )
          Ops.set(
            MailServer.MailPrevention,
            "VirusScanning",
            Convert.to_boolean(UI.QueryWidget(Id(:VirusScanning), :Value))
          )
          Ops.set(
            MailServer.MailPrevention,
            "SpamLearning",
            Convert.to_boolean(UI.QueryWidget(Id(:SpamLearning), :Value))
          )
          Ops.set(
            MailServer.MailPrevention,
            "VSCount",
            Convert.to_integer(UI.QueryWidget(Id(:VSCount), :Value))
          )
          title = _("Mail Server SPAM Basic Prevention Configuration")
          content = MailPreventionDialog(_CID, _CIDRBL)
          helptext = Ops.get_string(@HELPS, "MailPrevention", "Bla Bla Bla")
        elsif _FocusedContent == "MailRelaying"
          Ops.set(MailServer.MailRelaying, "Changed", true)
          _SMTPDTLSMode = Convert.to_string(
            UI.QueryWidget(Id(:SMTPDTLSMode), :CurrentButton)
          )
          if ret == :AddNewNetwork
            _NewNetwork = Convert.to_string(
              UI.QueryWidget(Id(:NewNetwork), :Value)
            )
            #TODO Checking if network is a real network
            Ops.set(
              MailServer.MailRelaying,
              "TrustedNetworks",
              Builtins.add(
                Ops.get_list(MailServer.MailRelaying, "TrustedNetworks", []),
                _NewNetwork
              )
            )
          end
          if ret == :DeleteNetwork
            _CurrentNetwork = Convert.to_string(
              UI.QueryWidget(Id(:TrustedNetworks), :CurrentItem)
            )
            Ops.set(
              MailServer.MailRelaying,
              "TrustedNetworks",
              Builtins.filter(
                Ops.get_list(MailServer.MailRelaying, "TrustedNetworks", [])
              ) { |network| network != _CurrentNetwork }
            )
          end
          Ops.set(MailServer.MailRelaying, "SMTPDTLSMode", _SMTPDTLSMode)
          if Convert.to_boolean(UI.QueryWidget(Id(:RequireSASL), :Value))
            Ops.set(MailServer.MailRelaying, "RequireSASL", "1")
          else
            Ops.set(MailServer.MailRelaying, "RequireSASL", "0")
          end
          title = _("Mail Server Relaying Configuration")
          content = MailRelayingDialog()
          helptext = Ops.get_string(@HELPS, "MailRelaying", "Bla Bla Bla")
        elsif _FocusedContent == "MailLocalDelivery"
          Ops.set(MailServer.MailLocalDelivery, "Changed", true)
          Ops.set(
            MailServer.MailLocalDelivery,
            "Type",
            Convert.to_string(UI.QueryWidget(Id(:Type), :CurrentButton))
          )
          if UI.WidgetExists(Id(:Repository)) &&
              UI.WidgetExists(Id(:MailboxType)) &&
              UI.WidgetExists(Id(:MailboxSize))
            if UI.QueryWidget(Id(:Repository), :CurrentButton) == "varspool"
              Ops.set(
                MailServer.MailLocalDelivery,
                "SpoolDirectory",
                "/var/spool/mail"
              )
            else
              Ops.set(
                MailServer.MailLocalDelivery,
                "SpoolDirectory",
                "$HOME/Mail"
              )
            end
            if UI.QueryWidget(Id(:MailboxType), :CurrentButton) == "mdir"
              Ops.set(
                MailServer.MailLocalDelivery,
                "SpoolDirectory",
                Ops.add(
                  Ops.get_string(
                    MailServer.MailLocalDelivery,
                    "SpoolDirectory",
                    ""
                  ),
                  "/"
                )
              )
            end
            if UI.QueryWidget(Id(:MailboxSize), :CurrentButton) == "NoLimit"
              Ops.set(MailServer.MailLocalDelivery, "MailboxSizeLimit", "0")
            else
              Ops.set(
                MailServer.MailLocalDelivery,
                "MailboxSizeLimit",
                Builtins.tostring(UI.QueryWidget(Id(:MailboxSizeLimit), :Value))
              )

              if Ops.get_string(
                  MailServer.MailLocalDelivery,
                  "MailboxSizeLimit",
                  "0"
                ) == "0"
                Ops.set(MailServer.MailLocalDelivery, "MailboxSizeLimit", "1")
              end
            end
          end
          if UI.WidgetExists(Id(:ImapSecurity)) &&
              UI.WidgetExists(Id(:QuotaLimit)) &&
              UI.WidgetExists(Id(:HardQuotaLimit))
            Ops.set(
              MailServer.MailLocalDelivery,
              "MailboxSizeLimit",
              Builtins.tostring(UI.QueryWidget(Id(:MailboxSizeLimit), :Value))
            )
            Ops.set(
              MailServer.MailLocalDelivery,
              "QuotaLimit",
              Builtins.tostring(UI.QueryWidget(Id(:QuotaLimit), :Value))
            )
            Ops.set(
              MailServer.MailLocalDelivery,
              "ImapIdleTime",
              Builtins.tostring(UI.QueryWidget(Id(:ImapIdleTime), :Value))
            )
            Ops.set(
              MailServer.MailLocalDelivery,
              "PopIdleTime",
              Builtins.tostring(UI.QueryWidget(Id(:PopIdleTime), :Value))
            )
            Ops.set(
              MailServer.MailLocalDelivery,
              "FallBackMailbox",
              UI.QueryWidget(Id(:FallBackMailbox), :Value)
            )
            if Convert.to_boolean(UI.QueryWidget(Id(:ImapSecurity), :Value))
              Ops.set(MailServer.MailLocalDelivery, "Security", "1")
            else
              Ops.set(MailServer.MailLocalDelivery, "Security", "0")
            end

            if Convert.to_boolean(UI.QueryWidget(Id(:HardQuotaLimit), :Value))
              Ops.set(MailServer.MailLocalDelivery, "HardQuotaLimit", "1")
            else
              Ops.set(MailServer.MailLocalDelivery, "HardQuotaLimit", "0")
            end
            if Convert.to_boolean(
                UI.QueryWidget(Id(:AlternateNameSpace), :Value)
              )
              Ops.set(MailServer.MailLocalDelivery, "AlternateNameSpace", "1")
            else
              Ops.set(MailServer.MailLocalDelivery, "AlternateNameSpace", "0")
            end
          end
          title = _("Mail Server Local Delivery Configuration")
          content = MailLocalDeliveryDialog()
          helptext = Ops.get_string(@HELPS, "MailLocalDelivery", "Bla Bla Bla")
        elsif _FocusedContent == "FetchingMail"
          Ops.set(MailServer.FetchingMail, "Changed", true)
          if ret == :Add
            _Job = FetchmailAddItem()
            if Ops.get_string(_Job, "server", "") != "" &&
                Ops.get_string(_Job, "password", "") != "" &&
                Ops.get_string(_Job, "remote_user", "") != "" &&
                Ops.get_string(_Job, "local_user", "") != ""
              Ops.set(
                MailServer.FetchingMail,
                "Items",
                Builtins.add(
                  Ops.get_list(MailServer.FetchingMail, "Items", []),
                  _Job
                )
              )
            end
          elsif ret == :Delete
            _IID = Convert.to_integer(UI.QueryWidget(Id(:table), :CurrentItem))
            my_id = 0
            _Jobs = Ops.get_list(MailServer.FetchingMail, "Items", [])
            Ops.set(MailServer.FetchingMail, "Items", [])
            Builtins.foreach(_Jobs) do |_Job|
              if my_id != _IID
                Ops.set(
                  MailServer.FetchingMail,
                  "Items",
                  Builtins.add(
                    Ops.get_list(MailServer.FetchingMail, "Items", []),
                    _Job
                  )
                )
              end
              my_id = Ops.add(my_id, 1)
            end
          elsif ret == :FetchByDialIn
            if Convert.to_boolean(UI.QueryWidget(Id(:FetchByDialIn), :Value))
              Ops.set(MailServer.FetchingMail, "FetchByDialIn", "1")
            else
              Ops.set(MailServer.FetchingMail, "FetchByDialIn", "0")
            end
          elsif ret == :FetchMailSteady
            if Convert.to_boolean(UI.QueryWidget(Id(:FetchMailSteady), :Value))
              Ops.set(MailServer.FetchingMail, "FetchMailSteady", "1")
            else
              Ops.set(MailServer.FetchingMail, "FetchMailSteady", "0")
            end
          end
          if UI.WidgetExists(Id(:FetchingInterval))
            Ops.set(
              MailServer.FetchingMail,
              "FetchingInterval",
              Builtins.tostring(UI.QueryWidget(Id(:FetchingInterval), :Value))
            )
          end
          if !UI.WidgetExists(Id(:FetchByDialIn))
            Ops.set(MailServer.FetchingMail, "FetchByDialIn", "0")
          end
          if UI.WidgetExists(Id(:Interface))
            Ops.set(
              MailServer.FetchingMail,
              "Interface",
              Convert.to_string(UI.QueryWidget(Id(:Interface), :Value))
            )
          end
          title = _("Mail Server Mail Fetching Configuration")
          content = FetchingMailDialog()
          helptext = Ops.get_string(@HELPS, "FetchingMail", "Bla Bla Bla")
        elsif _FocusedContent == "MailLocalDomains"
          _CID = Convert.to_string(UI.QueryWidget(Id(:table), :CurrentItem))
          if ret == :Change
            ShowMailLocalDomain(_CID, "change")
          elsif ret == :Add
            ShowMailLocalDomain(_CID, "add")
          elsif ret == :Delete
            Ops.set(MailServer.MailLocalDomains, "Changed", true)
            _Domains = Ops.get_list(MailServer.MailLocalDomains, "Domains", [])
            Ops.set(MailServer.MailLocalDomains, "Domains", [])
            Builtins.foreach(_Domains) do |_Domain|
              if _CID != Ops.get_string(_Domain, "Name", "")
                Ops.set(
                  MailServer.MailLocalDomains,
                  "Domains",
                  Builtins.add(
                    Ops.get_list(MailServer.MailLocalDomains, "Domains", []),
                    _Domain
                  )
                )
              end
            end
          end
          if !CheckMainDomain()
            _FocusedContent = "MailLocalDomains"
            ret = "MailLocalDomains"
            UI.SetFocus(Id("MailLocalDomains"))
          end
          title = _("Mail Server Local Domain Configuration")
          content = MailLocalDomainsDialog(_CID)
          helptext = Ops.get_string(@HELPS, "MailLocalDomains", "Bla Bla Bla")
        end

        if ret == :wizardTree
          ret = Wizard.QueryTreeItem
          Builtins.y2milestone("Selected: %1", ret)
        end
        if ret == "GlobalSettings" && _FocusedContent != "GlobalSettings"
          content = GlobalSettingsDialog()
          title = _("Mail Server Global Settings")
          helptext = Ops.get_string(@HELPS, "GlobalSettings", "Bla Bla Bla")
          focus_changed = true
          _FocusedContent = "GlobalSettings"
        elsif ret == "MailTransports" && _FocusedContent != "MailTransports"
          content = MailTransportsDialog()
          title = _("Mail Server Transport Configuration")
          helptext = Ops.get_string(@HELPS, "MailTransports", "Bla Bla Bla")
          focus_changed = true
          _FocusedContent = "MailTransports"
        elsif ret == "MailPrevention" && _FocusedContent != "MailPrevention"
          content = MailPreventionDialog(_CID, _CIDRBL)
          title = _("Mail Server SPAM Basic Prevention Configuration")
          helptext = Ops.get_string(@HELPS, "MailPrevention", "Bla Bla Bla")
          focus_changed = true
          _FocusedContent = "MailPrevention"
        elsif ret == "MailRelaying" && _FocusedContent != "MailRelaying"
          content = MailRelayingDialog()
          title = _("Mail Server Relaying Configuration")
          helptext = Ops.get_string(@HELPS, "MailRelaying", "Bla Bla Bla")
          focus_changed = true
          _FocusedContent = "MailRelaying"
        elsif ret == "MailLocalDelivery" &&
            _FocusedContent != "MailLocalDelivery"
          content = MailLocalDeliveryDialog()
          title = _("Mail Server Local Delivery Configuration")
          helptext = Ops.get_string(@HELPS, "MailLocalDelivery", "Bla Bla Bla")
          focus_changed = true
          _FocusedContent = "MailLocalDelivery"
        elsif ret == "FetchingMail" && _FocusedContent != "FetchingMail"
          content = FetchingMailDialog()
          title = _("Mail Server Mail Fetching Configuration")
          helptext = Ops.get_string(@HELPS, "FetchingMail", "Bla Bla Bla")
          focus_changed = true
          _FocusedContent = "FetchingMail"
        elsif ret == "MailLocalDomains" && _FocusedContent != "MailLocalDomains"
          CheckMainDomain()
          content = MailLocalDomainsDialog("")
          title = _("Mail Server Local Domain Configuration")
          helptext = Ops.get_string(@HELPS, "MailLocalDomains", "Bla Bla Bla")
          focus_changed = true
          _FocusedContent = "MailLocalDomains"
        end
        if ret != :cancel && ret != :abort && ret != :next
          Wizard.SetContents(title, content, helptext, false, true)
          Wizard.SetDesktopIcon("mail")
          UI.WizardCommand(term(:SetBackButtonLabel, ""))
          UI.WizardCommand(term(:SetNextButtonLabel, _("OK")))
          if UI.WidgetExists(Id(:table))
            UI.ChangeWidget(Id(:table), :CurrentItem, _CID)
          end
          if !MailServer.CertExist
            # If there is no certificate you cannot use server side TLS SSL
            if UI.WidgetExists(Id(:SMTPDTLSMode))
              UI.ChangeWidget(Id(:SMTPDTLSMode), :Enabled, false)
            end
            if UI.WidgetExists(Id(:ImapSecurity))
              UI.ChangeWidget(Id(:ImapSecurity), :Enabled, false)
            end
            Ops.set(MailServer.MailLocalDelivery, "Security", "0")
            Ops.set(MailServer.MailRelaying, "SMTPDTLSMode", "none")
          end 
          # if (focus_changed)
          # 	  {
          # 	      UI::SetFocus (`id (`wizardTree));
          # 	  }
        end
      end
      UI.CloseDialog
      deep_copy(ret)
    end
  end
end
