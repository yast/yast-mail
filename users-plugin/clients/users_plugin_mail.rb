# encoding: utf-8

# File:
#        users_plugin_ldap_all.ycp
#
# Package:
#        Configuration of Users
#
# Summary:
#        This is part GUI of UsersPluginMail - plugin for editing all LDAP
#        user/group attributes.
#
# $Id: users_plugin_mail.ycp 36210 2007-02-16 11:28:50Z varkoly $
module Yast
  class UsersPluginMailClient < Client
    def main
      Yast.import "UI"
      textdomain "mail" # use own textdomain for new plugins

      Yast.import "Label"
      Yast.import "Popup"
      Yast.import "Report"
      Yast.import "Wizard"
      Yast.import "Hostname"

      Yast.import "Ldap"
      Yast.import "LdapPopup"
      Yast.import "Users"
      Yast.import "UsersLDAP"
      Yast.import "UsersPluginMail" # plugin module

      Yast.import "YaPI::MailServer"

      @ret = nil
      @func = ""
      @config = {}
      @data = {}

      # Check arguments
      if Ops.greater_than(Builtins.size(WFM.Args), 0) &&
          Ops.is_string?(WFM.Args(0))
        @func = Convert.to_string(WFM.Args(0))
        if Ops.greater_than(Builtins.size(WFM.Args), 1) &&
            Ops.is_map?(WFM.Args(1))
          @config = Convert.convert(
            WFM.Args(1),
            :from => "any",
            :to   => "map <string, any>"
          )
        end
        if Ops.greater_than(Builtins.size(WFM.Args), 2) &&
            Ops.is_map?(WFM.Args(2))
          @data = Convert.convert(
            WFM.Args(2),
            :from => "any",
            :to   => "map <string, any>"
          )
        end
      end
      Builtins.y2milestone("----------------------------------------")
      Builtins.y2milestone("users plugin started: Mail")
      Builtins.y2milestone("config=%1", @config)

      Builtins.y2debug("func=%1", @func)
      Builtins.y2debug("config=%1", @config)
      Builtins.y2debug("data=%1", @data)

      if @func == "Summary"
        @ret = UsersPluginMail.Summary(@config, {})
      elsif @func == "Name"
        @ret = UsersPluginMail.Name(@config, {})
      elsif @func == "Dialog"
        @imapadmpw = Ldap.bind_pass
        @MailLocalDomains = Convert.convert(
          YaPI::MailServer.ReadMailLocalDomains(@imapadmpw),
          :from => "any",
          :to   => "map <string, any>"
        )
        @MailLocalDelivery = Convert.convert(
          YaPI::MailServer.ReadMailLocalDelivery(@imapadmpw),
          :from => "any",
          :to   => "map <string, any>"
        )

        # See RFC 2822, 3.4
        # But for now, no-spaces@valid_domainname
        # @param [String] address an address to check
        # @return valid?check_mail_address
        def check_mail_address(address)
          parts = Builtins.splitstring(address, "@")
          return false if Builtins.size(parts) != 2
          address = Ops.get(parts, 0, "")

          address != "" && Builtins.findfirstof(address, " ") == nil &&
            Hostname.CheckDomain(Ops.get(parts, 1, ""))
        end

        # Edit EMAIL Address
        #
        # @param old EMAIL
        # @return new EMAIL or old EMAIL, if the user abort the dialog
        def editEMAIL(email)
          UI.OpenDialog(
            Opt(:decorated),
            HBox(
              HSpacing(2),
              VBox(
                VSpacing(1),
                # popup window header
                Heading(_("Change E-Mail")),
                VSpacing(1),
                TextEntry(Id(:entry), _("&E-Mail Address:"), email),
                VSpacing(1),
                HBox(
                  PushButton(Id(:ok), Opt(:default, :key_F10), Label.OKButton),
                  HStretch(),
                  PushButton(Id(:cancel), Opt(:key_F9), Label.AbortButton)
                ), # push button label
                VSpacing(1)
              ),
              HSpacing(2)
            )
          )

          UI.SetFocus(Id(:entry))
          ui = nil
          newEmail = ""
          begin
            ui = Convert.to_symbol(UI.UserInput)
            newEmail = Convert.to_string(UI.QueryWidget(Id(:entry), :Value))
            if !check_mail_address(newEmail)
              Popup.Error(_("Invalid e-mail format."))
              ui = :again
            end
          end until Builtins.contains([:ok, :cancel], ui)
          UI.CloseDialog
          if ui == :ok && Ops.greater_than(Builtins.size(newEmail), 0)
            return newEmail
          else
            return email
          end
        end

        # Creates EMAIL items
        # @return a list EMAIL items formated for a UI table
        def getEMAILList
          result = []
          i = 0

          if Ops.is_string?(Ops.get(@data, "suseMailAcceptAddress", "")) &&
              Ops.greater_than(
                Builtins.size(
                  Ops.get_string(@data, "suseMailAcceptAddress", "")
                ),
                0
              )
            result = [
              Item(Id(i), Ops.get_string(@data, "suseMailAcceptAddress", ""))
            ]
            # transforming to list
            Ops.set(
              @data,
              "suseMailAcceptAddress",
              [Ops.get_string(@data, "suseMailAcceptAddress", "")]
            )
          elsif Ops.is_list?(Ops.get(@data, "suseMailAcceptAddress", []))
            Builtins.foreach(Ops.get_list(@data, "suseMailAcceptAddress", [])) do |element|
              result = Builtins.add(result, Item(Id(i), element))
              i = Ops.add(i, 1)
            end
          end
          deep_copy(result)
        end
        # Creates EMAIL items
        # @return a list EMAIL items formated for a UI table
        def getDomainList
          _Domains = []
          Builtins.foreach(Ops.get_list(@MailLocalDomains, "Domains", [])) do |_Domain|
            if Ops.get_string(_Domain, "Type", "") != "none"
              _Domains = Builtins.add(
                _Domains,
                Ops.get_string(_Domain, "Name", "")
              )
            end
          end
          deep_copy(_Domains)
        end

        # define the dialog for this plugin and return it's contents

        @caption = UsersPluginMail.Name(@config, {})
        @what = Ops.get_string(@config, "what", "user")
        @action = Ops.get_string(@data, "what", "")

        @tmp_data = {}
        @object_class = Convert.convert(
          Builtins.sort(Ops.get_list(@data, "objectClass", [])),
          :from => "list",
          :to   => "list <string>"
        )

        # if this plugin wasn't present in default plugin set, we have to call
        # BeforeAdd/BeforeEdit e.g. to get object class!
        if !Builtins.contains(
            Ops.get_list(@data, "plugins", []),
            "UsersPluginMail"
          )
          if @action == "add_user" || @action == "add_group"
            @data = UsersPluginMail.AddBefore(@config, @data)
          elsif @action == "edit_user" || @action == "edit_group"
            @data = UsersPluginMail.EditBefore(@config, @data)
          end
          @object_class = Convert.convert(
            Builtins.sort(Ops.get_list(@data, "objectClass", [])),
            :from => "list",
            :to   => "list <string>"
          )
          Ops.set(@tmp_data, "objectClass", @object_class)
        end

        # helptext 1/3
        @help_text = _(
          "<p>In this dialog You can configure the mail settings of an user .</p>"
        ) +
          # helptext 2/3
          _(
            "<p>First you can set the mail addresses and aliases for the user.</p>"
          ) +
          # helptext 3/3
          _(
            "<p>If you have selected \"imap\" for the local delivery of mails, you can set the size limit for the users mail box.\n           If you do not set any value the mail box size is unlimited.</p>"
          )

        @items = nil
        @used_attributes = []
        @new_attributes = []
        @modified = false
        @emailTermList = getEMAILList
        @DomainList = getDomainList

        @buttons = VBox()
        # To translators: pushbutton label
        @buttons = Builtins.add(
          @buttons,
          HBox(
            HWeight(
              1,
              PushButton(Id(:deleteEmail), Opt(:key_F5), Label.DeleteButton)
            )
          )
        )
        @buttons = Builtins.add(
          @buttons,
          HBox(
            HWeight(
              1,
              PushButton(Id(:editEmail), Opt(:key_F4), Label.EditButton)
            )
          )
        )
        @buttons = Builtins.add(@buttons, VStretch())
        # To translators: pushbutton label
        @buttons = Builtins.add(
          @buttons,
          HBox(
            HWeight(1, PushButton(Id(:addEmail), Opt(:key_F3), Label.AddButton))
          )
        )

        @editEmail = VBox()
        @editEmail = Builtins.add(
          @editEmail,
          HBox(
            VSpacing(5),
            Table(
              Id(:table),
              Opt(:notify, :immediate),
              Header(
                # To translators: table headers
                # please let the spaces
                _("E-Mail Addresses                        ")
              ),
              @emailTermList
            )
          )
        )
        @editEmail = Builtins.add(
          @editEmail,
          HBox(
            HWeight(10, TextEntry(Id(:id_emailname), " ")),
            HWeight(1, VBox(Label(" "), Label("@"))),
            HWeight(10, ComboBox(Id(:domain), " ", @DomainList))
          )
        )

        @emails = HBox()
        @emails = Builtins.add(@emails, HWeight(3, @editEmail))
        @emails = Builtins.add(@emails, HWeight(1, @buttons))

        @imap = VBox()
        @intimapquota = -1
        if Builtins.haskey(@data, "suseImapQuota") &&
            Ops.get_string(@data, "suseImapQuota", "10000") != nil
          @intimapquota = Builtins.tointeger(
            Ops.get_string(@data, "suseImapQuota", "10000")
          )
        end

        if Ops.get_string(@data, "localdeliverytype", "local") == "imap"
          @imap = Frame(
            _("IMAP Quota"),
            VBox(
              HBox(
                CheckBox(
                  Id(:enableImapquota),
                  Opt(:notify),
                  _("Enable IMAP Quota"),
                  Ops.greater_or_equal(@intimapquota, 0)
                ),
                HSpacing(5),
                IntField(
                  Id(:imapquota),
                  _("in kByte"),
                  1,
                  10000000,
                  Ops.greater_or_equal(@intimapquota, 0) ? @intimapquota : 10000
                )
              ),
              VSpacing(0.5),
              Left(
                Label(
                  Builtins.sformat(
                    _("IMAP quota already in use: %1 kByte"),
                    Ops.get_string(@data, "imapquotaused", "0") != nil ?
                      Ops.get_string(@data, "imapquotaused", "0") :
                      "0"
                  )
                )
              )
            )
          )
        end


        @contents = HBox(
          HSpacing(1.5),
          VBox(VSpacing(0.5), @emails, VSpacing(0.5), @imap),
          HSpacing(1.5)
        )

        Wizard.CreateDialog
        Wizard.SetDesktopIcon("users")

        # dialog caption
        Wizard.SetContentsButtons(
          _("Mail Settings"),
          @contents,
          @help_text,
          Label.BackButton,
          Label.NextButton
        )

        Wizard.HideAbortButton

        @ret = :next
        begin
          UI.ChangeWidget(
            Id(:deleteEmail),
            :Enabled,
            UI.QueryWidget(Id(:table), :CurrentItem) != nil
          )
          UI.ChangeWidget(
            Id(:editEmail),
            :Enabled,
            UI.QueryWidget(Id(:table), :CurrentItem) != nil
          )
          if Ops.get_string(@data, "localdeliverytype", "local") == "imap"
            UI.ChangeWidget(
              Id(:imapquota),
              :Enabled,
              Convert.to_boolean(UI.QueryWidget(Id(:enableImapquota), :Value))
            )
          end

          @ret = UI.UserInput

          if @ret == :addEmail
            @emailName = Ops.add(
              Ops.add(
                Convert.to_string(UI.QueryWidget(Id(:id_emailname), :Value)),
                "@"
              ),
              Convert.to_string(UI.QueryWidget(Id(:domain), :Value))
            )

            if Ops.greater_than(Builtins.size(@emailName), 0)
              if check_mail_address(@emailName)
                if Builtins.contains(
                    Ops.get_list(@data, "suseMailAcceptAddress", []),
                    @emailName
                  )
                  Popup.Error(_("Entry already exists."))
                else
                  Ops.set(
                    @data,
                    "suseMailAcceptAddress",
                    Builtins.add(
                      Ops.get_list(@data, "suseMailAcceptAddress", []),
                      @emailName
                    )
                  )
                  UI.ChangeWidget(Id(:table), :Items, getEMAILList)
                  UI.ChangeWidget(Id(:id_emailname), :Value, "")
                end
              else
                Popup.Error(_("Invalid e-mail format."))
              end
            end
          end
          if @ret == :deleteEmail
            @id = Convert.to_integer(UI.QueryWidget(Id(:table), :CurrentItem))
            Ops.set(
              @data,
              "suseMailAcceptAddress",
              Builtins.remove(
                Ops.get_list(@data, "suseMailAcceptAddress", []),
                @id
              )
            )
            UI.ChangeWidget(Id(:table), :Items, getEMAILList)
          end
          if @ret == :editEmail
            @id = Convert.to_integer(UI.QueryWidget(Id(:table), :CurrentItem))
            @oldEMAIL = Ops.get_string(
              Ops.get_list(@data, "suseMailAcceptAddress", []),
              @id,
              ""
            )
            @newEMAIL = editEMAIL(@oldEMAIL)

            if Builtins.contains(
                Ops.get_list(@data, "suseMailAcceptAddress", []),
                @newEMAIL
              )
              Popup.Error(_("Entry already exists."))
            else
              Ops.set(
                @data,
                "suseMailAcceptAddress",
                Builtins.remove(
                  Ops.get_list(@data, "suseMailAcceptAddress", []),
                  @id
                )
              )
              Ops.set(
                @data,
                "suseMailAcceptAddress",
                Builtins.add(
                  Ops.get_list(@data, "suseMailAcceptAddress", []),
                  @newEMAIL
                )
              )
            end
            UI.ChangeWidget(Id(:table), :Items, getEMAILList)
          end

          if @ret == :next
            @err = UsersPluginMail.Check(
              @config,
              Convert.convert(
                Builtins.union(@data, @tmp_data),
                :from => "map",
                :to   => "map <string, any>"
              )
            )

            if @err != ""
              Report.Error(@err)
              @ret = :notnext
              next
            end

            # if this plugin wasn't in default set, we must save its name
            if !Builtins.contains(
                Ops.get_list(@data, "plugins", []),
                "UsersPluginMail"
              )
              Ops.set(
                @data,
                "plugins",
                Builtins.add(
                  Ops.get_list(@data, "plugins", []),
                  "UsersPluginMail"
                )
              )
            end
            if Builtins.size(Ops.get_list(@data, "suseMailAcceptAddress", [])) == 1
              Ops.set(
                @data,
                "suseMailAcceptAddress",
                Ops.get_string(
                  Ops.get_list(@data, "suseMailAcceptAddress", []),
                  0,
                  ""
                )
              )
            elsif Builtins.size(
                Ops.get_list(@data, "suseMailAcceptAddress", [])
              ) == 0
              Builtins.remove(@data, "suseMailAcceptAddress")
            end

            if Ops.get_string(@data, "localdeliverytype", "local") == "imap"
              if Convert.to_boolean(
                  UI.QueryWidget(Id(:enableImapquota), :Value)
                )
                Ops.set(
                  @data,
                  "suseImapQuota",
                  Convert.to_integer(UI.QueryWidget(Id(:imapquota), :Value))
                )
              else
                Ops.set(@data, "suseImapQuota", -1)
              end
            end
            if Ops.get_string(@data, "what", "") == "edit_user"
              Users.EditUser(@data)
            elsif Ops.get_string(@data, "what", "") == "add_user"
              Users.AddUser(@data)
            elsif Ops.get_string(@data, "what", "") == "edit_group"
              Users.EditGroup(@data)
            elsif Ops.get_string(@data, "what", "") == "add_group"
              Users.AddGroup(@data)
            end
          end
        end until Ops.is_symbol?(@ret) &&
          Builtins.contains(
            [:next, :abort, :back, :cancel],
            Convert.to_symbol(@ret)
          )

        Wizard.CloseDialog
      else
        Builtins.y2error("unknown function: %1", @func)
        @ret = false
      end

      Builtins.y2debug("ret=%1", @ret)
      Builtins.y2milestone("users plugin finished")
      Builtins.y2milestone("----------------------------------------")

      deep_copy(@ret)
    end
  end
end

Yast::UsersPluginMailClient.new.main
