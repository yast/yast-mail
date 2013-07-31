# encoding: utf-8

# File:
#        users_plugin_mail_groups.ycp
#
# Package:
#        Configuration of Mail Server
#
# Summary:
#        This is part GUI of UsersPluginMail - plugin for editing all LDAP
#        user/group attributes.
#
# $Id: users_plugin_mail_groups.ycp 28707 2006-03-08 14:39:26Z varkoly $
module Yast
  class UsersPluginMailGroupsClient < Client
    def main
      Yast.import "UI"
      textdomain "mail" # use own textdomain for new plugins

      Yast.import "Label"
      Yast.import "Popup"
      Yast.import "Report"
      Yast.import "Wizard"
      Yast.import "Hostname"

      Yast.import "Ldap"
      Yast.import "Users"
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
        # define the dialog for this plugin and return it's contents

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
        @deliverytomember = true
        @sharedfolder = false
        @enableImpapquota = false

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

          if Ops.is_string?(Ops.get(@data, "suseMailForwardAddress", "")) &&
              Ops.greater_than(
                Builtins.size(
                  Ops.get_string(@data, "suseMailForwardAddress", "")
                ),
                0
              )
            result = [
              Item(Id(i), Ops.get_string(@data, "suseMailForwardAddress", ""))
            ]
            # transforming to list
            Ops.set(
              @data,
              "suseMailForwardAddress",
              [Ops.get_string(@data, "suseMailForwardAddress", "")]
            )
          elsif Ops.is_list?(Ops.get(@data, "suseMailForwardAddress", []))
            Builtins.foreach(Ops.get_list(@data, "suseMailForwardAddress", [])) do |element|
              result = Builtins.add(result, Item(Id(i), element))
              i = Ops.add(i, 1)
            end
          end

          deep_copy(result)
        end


        @caption = UsersPluginMail.Name(@config, {})
        @what = Ops.get_string(@config, "what", "user")
        @action = Ops.get_string(@data, "what", "")

        if Ops.get_string(@data, "suseDeliveryToMember", "no") == "yes"
          @deliverytomember = true
        end
        if Ops.get_string(@data, "suseDeliveryToFolder", "no") == "yes"
          @sharedfolder = true
        end

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
            "<p>If you have selected \"cyrus\" for the local delivery of mails, you can set the size limit for the users mail box.\n           If you do not set any value the mail box size is unlimited.</p>"
          )

        @items = nil
        @used_attributes = []
        @new_attributes = []
        @modified = false
        @emailTermList = getEMAILList

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
                _("Forwarding E-Mail Addresses                        ")
              ),
              @emailTermList
            )
          )
        )
        @editEmail = Builtins.add(
          @editEmail,
          HBox(TextEntry(Id(:id_emailname), " "))
        )

        @emails = HBox()
        @emails = Builtins.add(@emails, HWeight(3, @editEmail))
        @emails = Builtins.add(@emails, HWeight(1, @buttons))

        @imap = VBox()
        @shared = VBox()
        @intimapQuota = -1
        if Builtins.haskey(@data, "imapQuota") &&
            Ops.get_string(@data, "imapQuota", "10000") != nil
          @intimapQuota = Builtins.tointeger(
            Ops.get_string(@data, "imapQuota", "-1")
          )
        end
        @shared = Frame(
          _("Delivery of group Mails"),
          VBox(
            Left(
              CheckBox(
                Id(:deliverytomember),
                _("Enable Delivery to the Members"),
                @deliverytomember
              )
            )
          )
        )

        if Ops.get_string(@data, "localdeliverytype", "local") == "cyrus"
          @shared = Frame(
            _("Delivery of group Mails"),
            VBox(
              Left(
                CheckBox(
                  Id(:deliverytomember),
                  Opt(:notify),
                  _("Enable Delivery to the Members"),
                  @deliverytomember
                )
              )
            )
          )
          @imap = Frame(
            _("IMAP Quota"),
            VBox(
              Left(
                CheckBox(
                  Id(:sharedfolder),
                  Opt(:notify),
                  _("Enable Shared Folder"),
                  @sharedfolder
                )
              ),
              Left(
                CheckBox(
                  Id(:enableImpapquota),
                  Opt(:notify),
                  _("Enable IMAP Quota"),
                  Ops.greater_or_equal(@intimapQuota, 0)
                )
              ),
              HBox(
                IntField(
                  Id(:imapQuota),
                  _("in kByte"),
                  1,
                  10000000,
                  Ops.greater_or_equal(@intimapQuota, 0) ? @intimapQuota : 10000
                ),
                HStretch()
              ),
              Left(
                Label(
                  Builtins.sformat(
                    _("IMAP quota already in use: %1 kByte"),
                    Ops.get_string(@data, "imapQuotaused", "0") != nil ?
                      Ops.get_string(@data, "imapQuotaused", "0") :
                      "0"
                  )
                )
              )
            )
          )
        end


        @contents = HBox(
          HSpacing(1.5),
          VBox(
            VSpacing(0.5),
            @emails,
            VSpacing(0.5),
            @shared,
            VSpacing(0.5),
            @imap
          ),
          HSpacing(1.5)
        )

        Wizard.CreateDialog
        Wizard.SetDesktopIcon("users")

        # dialog caption
        Wizard.SetContentsButtons(
          Ops.add(
            Ops.add(
              _("Mail Settings for the group:") + " \"",
              Ops.get_string(@data, "cn", "")
            ),
            "\""
          ),
          @contents,
          @help_text,
          Label.BackButton,
          Label.NextButton
        )

        Wizard.HideAbortButton

        @ret = :next
        begin
          @enableImpapquota = Convert.to_boolean(
            UI.QueryWidget(Id(:enableImpapquota), :Value)
          )
          @sharedfolder = Convert.to_boolean(
            UI.QueryWidget(Id(:sharedfolder), :Value)
          )
          @deliverytomember = Convert.to_boolean(
            UI.QueryWidget(Id(:deliverytomember), :Value)
          )

          if @ret == :deliverytomember
            @sharedfolder = !@deliverytomember
            UI.ChangeWidget(Id(:sharedfolder), :Value, @sharedfolder)
          end
          if @ret == :sharedfolder
            @deliverytomember = !@sharedfolder
            UI.ChangeWidget(Id(:deliverytomember), :Value, @deliverytomember)
          end

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

          if Ops.get_string(@data, "localdeliverytype", "local") == "cyrus" &&
              !@deliverytomember
            UI.ChangeWidget(Id(:sharedfolder), :Enabled, true)
            if @sharedfolder
              UI.ChangeWidget(Id(:enableImpapquota), :Enabled, true)
              UI.ChangeWidget(Id(:imapQuota), :Enabled, @enableImpapquota)
            else
              UI.ChangeWidget(Id(:enableImpapquota), :Enabled, false)
              UI.ChangeWidget(Id(:imapQuota), :Enabled, false)
            end
          else
            # If there is no cyrus, we have only delivery to member
            @deliverytomember = true
            UI.ChangeWidget(Id(:deliverytomember), :Value, @deliverytomember)
            UI.ChangeWidget(Id(:enableImpapquota), :Enabled, false)
            UI.ChangeWidget(Id(:imapQuota), :Enabled, false)
          end

          @ret = UI.UserInput

          if @ret == :addEmail
            @emailName = Convert.to_string(
              UI.QueryWidget(Id(:id_emailname), :Value)
            )

            if Ops.greater_than(Builtins.size(@emailName), 0)
              if check_mail_address(@emailName)
                if Builtins.contains(
                    Ops.get_list(@data, "suseMailForwardAddress", []),
                    @emailName
                  )
                  Popup.Error(_("Entry already exists."))
                else
                  Ops.set(
                    @data,
                    "suseMailForwardAddress",
                    Builtins.add(
                      Ops.get_list(@data, "suseMailForwardAddress", []),
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
              "suseMailForwardAddress",
              Builtins.remove(
                Ops.get_list(@data, "suseMailForwardAddress", []),
                @id
              )
            )
            UI.ChangeWidget(Id(:table), :Items, getEMAILList)
          end
          if @ret == :editEmail
            @id = Convert.to_integer(UI.QueryWidget(Id(:table), :CurrentItem))
            @oldEMAIL = Ops.get_string(
              Ops.get_list(@data, "suseMailForwardAddress", []),
              @id,
              ""
            )
            @newEMAIL = editEMAIL(@oldEMAIL)

            if Builtins.contains(
                Ops.get_list(@data, "suseMailForwardAddress", []),
                @newEMAIL
              )
              Popup.Error(_("Entry already exists."))
            else
              Ops.set(
                @data,
                "suseMailForwardAddress",
                Builtins.remove(
                  Ops.get_list(@data, "suseMailForwardAddress", []),
                  @id
                )
              )
              Ops.set(
                @data,
                "suseMailForwardAddress",
                Builtins.add(
                  Ops.get_list(@data, "suseMailForwardAddress", []),
                  @newEMAIL
                )
              )
            end
            UI.ChangeWidget(Id(:table), :Items, getEMAILList)
          end
          if @ret == :next
            if Convert.to_boolean(UI.QueryWidget(Id(:deliverytomember), :Value))
              Ops.set(@data, "suseDeliveryToMember", "yes")
            else
              Ops.set(@data, "suseDeliveryToMember", "no")
            end
            # We put it everytime into the LDAP, and the ldap filter control if it is visible
            Ops.set(
              @data,
              "suseMailCommand",
              Ops.add(
                Ops.add(
                  Ops.add(
                    Ops.add(
                      "\"|/usr/bin/formail -I \\\"From \\\" |/usr/lib/cyrus/bin/deliver -r ",
                      Ops.get_string(@data, "cn", "")
                    ),
                    " -a cyrus -m "
                  ),
                  Ops.get_string(@data, "cn", "")
                ),
                "\""
              )
            )
            if Convert.to_boolean(UI.QueryWidget(Id(:sharedfolder), :Value))
              Ops.set(@data, "suseDeliveryToFolder", "yes")
            else
              Ops.set(@data, "suseDeliveryToFolder", "no")
            end

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
            if Builtins.size(Ops.get_list(@data, "suseMailForwardAddress", [])) == 1
              Ops.set(
                @data,
                "suseMailForwardAddress",
                Ops.get_string(
                  Ops.get_list(@data, "suseMailForwardAddress", []),
                  0,
                  ""
                )
              )
            elsif Builtins.size(
                Ops.get_list(@data, "suseMailForwardAddress", [])
              ) == 0
              Builtins.remove(@data, "suseMailForwardAddress")
            end

            if Ops.get_string(@data, "localdeliverytype", "local") == "cyrus"
              if Convert.to_boolean(
                  UI.QueryWidget(Id(:enableImpapquota), :Value)
                )
                Ops.set(
                  @data,
                  "imapQuota",
                  Convert.to_integer(UI.QueryWidget(Id(:imapQuota), :Value))
                )
              else
                Ops.set(@data, "imapQuota", -1)
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

Yast::UsersPluginMailGroupsClient.new.main
