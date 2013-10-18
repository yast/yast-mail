# encoding: utf-8

# File:
#   include/mail/wj.ycp
#
# Package:
#   Configuration of mail
#
# Summary:
#   Widget Juggler. One of the predecessors of CWM.
#
# Authors:
#   Martin Vidner <mvidner@suse.cz>
#
# $Id$
#
# <ol>
# <li> Widget functions to make moving widgets between dialogs easier.
# <li> Table editing helpers
# </ol>
module Yast
  module MailWjInclude
    def initialize_mail_wj(include_target)
      Yast.import "UI"

      textdomain "mail" # shoudn't be necessary

      Yast.include include_target, "mail/widgets.rb"

      @edit_touched = false
    end

    # ----------------------------------------------------------------

    # @param [Array<Hash>] data	a list of structs
    # @param [Array<String>] keys	which members to put in the table
    # @return	an item list
    def makeItems(data, keys)
      data = deep_copy(data)
      keys = deep_copy(keys)
      i = 0
      Builtins.maplist(data) do |d|
        t = Item(Id(i))
        i = Ops.add(i, 1)
        Builtins.foreach(keys) do |k|
          t = Builtins.add(t, Ops.get_string(d, k, ""))
        end
        deep_copy(t)
      end
    end





    # A generic handler for editing tables.
    # The current item of table_widget
    # makeItems (new_data, keys) is used to fill table_widget
    # @param [Symbol] action	`add, `edit or `delete
    # @param [Array<Hash>] data		the data edited using the table
    # @param [Array<String>] keys		keys of respective columns
    # @param editEntry	a function to edit an entry:
    #			gets the current entry and list of othe entries as parameters
    # @param [Object] table_widget	id of the table (usually a symbol)
    # @return		the edited data
    def EditTable(action, data, keys, editEntryP, table_widget)
      data = deep_copy(data)
      keys = deep_copy(keys)
      editEntryP = deep_copy(editEntryP)
      table_widget = deep_copy(table_widget)
      new_data = nil
      entryno = Convert.to_integer(
        UI.QueryWidget(Id(table_widget), :CurrentItem)
      )
      touched = false

      editEntry = deep_copy(editEntryP) #FIXME

      if action == :add
        entry = editEntry.call({}, data)
        if Ops.greater_than(Builtins.size(entry), 0)
          new_data = Builtins.add(data, entry)
          touched = true
        else
          new_data = deep_copy(data)
        end
      elsif action == :edit
        # edit known fields, preserve unknown fields
        old_entry = Ops.get(data, entryno, {})
        entry = editEntry.call(old_entry, Builtins.remove(data, entryno))
        if Ops.greater_than(Builtins.size(entry), 0)
          i = 0
          new_data = Builtins.maplist(data) do |e|
            i = Ops.add(i, 1)
            Ops.subtract(i, 1) == entryno ?
              Builtins.union(old_entry, entry) :
              deep_copy(e)
          end
          touched = true
        else
          new_data = deep_copy(data)
        end
      elsif action == :delete
        new_data = Builtins.remove(data, entryno)
        touched = true
      else
        Builtins.y2error("Unknown EditTable action %1.", action)
        new_data = deep_copy(data) # be nice
      end

      if touched
        UI.ChangeWidget(Id(table_widget), :Items, makeItems(new_data, keys))
        @edit_touched = true
      end
      deep_copy(new_data)
    end

    # ----------------------------------------------------------------

    # Evaluate a function pointer, working around interpreter limitations
    # @param [Object] fp pointer to a functin without parameters returning
    #           boolean string symbol or list
    # @return its return value as any
    def evaluate_fp(fp)
      fp = deep_copy(fp)
      if Ops.is(fp, "boolean ()")
        boolean_fp = Convert.convert(fp, :from => "any", :to => "boolean ()")
        return boolean_fp.call
      end
      if Ops.is(fp, "list ()")
        list_fp = Convert.convert(fp, :from => "any", :to => "list ()")
        return list_fp.call
      end
      if Ops.is(fp, "string ()")
        string_fp = Convert.convert(fp, :from => "any", :to => "string ()")
        return string_fp.call
      end
      if Ops.is(fp, "symbol ()")
        symbol_fp = Convert.convert(fp, :from => "any", :to => "symbol ()")
        return symbol_fp.call
      end
      # report as the caller
      Builtins.y2error(1, "evaluate_fp: Unexpected function pointer: %1", fp)
      nil
    end

    # Constructs a widget term.
    # Uses a global Widgets map.
    # Keys are symbols (ids), values are
    #
    # **Structure:**
    #
    #     widget_def
    #         `foo: $[
    #     	"widget": `TextEntry (),
    #     	"opt": `opt (`notify), // optional
    #     	"label": "&Foo",
    #     	// if there are choices, they are used to construct the widget,
    #     	// otherwise get is used
    #     	"choices": Choices_foo          // list ()
    #     	"help": _("&lt;p&gt;Foo!&lt;/p&gt;"), // used by WJ_MakeHelp, optional
    #     	"get": Get_foo,			// gets value from module to widget
    #     	"set": Set_foo,			// sets value from widget to module
    #     	// popups an error and returns false if invalid
    #     	"validate": ``(Validate_foo ()),// optional
    #     	],
    # @param [Symbol] id which widget
    # @return a widget term
    def WJ_MakeWidget(id)
      w_def = Ops.get_map(@Widgets, id, {})
      widget = Ops.get_term(w_def, "widget", CheckBox())
      return nil if widget == nil
      widget = Builtins.add(widget, Id(id))
      if Builtins.haskey(w_def, "opt")
        widget = Builtins.add(widget, Ops.get_term(w_def, "opt", Empty()))
      end
      widget = Builtins.add(widget, Ops.get_string(w_def, "label", "LABEL"))
      # if choices are defined (combo boxes ...), use them
      # otherwise set the value directly
      # TODO: verified only for TextEntry. Password, CheckBox, ComboBox

      # "choices" returns list, "get" returns string, symbol or boolean
      init = evaluate_fp(Ops.get(w_def, "choices", Ops.get(w_def, "get")))
      return Builtins.add(widget, init) if init != nil
      deep_copy(widget)
    end

    # Changes widget value using "get" (useful for widgets with choices).
    # Uses a global Widgets map. {#widget_def}
    # @param [Symbol] id which widget
    def WJ_GetWidget(id)
      # "get" returns string or boolean:
      e = evaluate_fp(Ops.get(@Widgets, [id, "get"]))
      UI.ChangeWidget(Id(id), :Value, e)

      nil
    end

    # Make a help string by concatenating
    # individual widget helps and other strings.
    # Uses a global Widgets map. {#widget_def}
    # @param [Array] items an item is<br>
    #   either	a string - use it<br>
    #   or		a symbol - lookup its help string in Widgets
    # @return concatenated strings
    def WJ_MakeHelp(items)
      items = deep_copy(items)
      ret = ""
      Builtins.foreach(items) do |item|
        if !Ops.is_string?(item)
          item = Ops.get_string(@Widgets, [item, "help"], "")
        end
        ret = Ops.add(ret, Convert.to_string(item))
      end
      ret
    end

    # A helper for WJ_Validate.
    # @param [Symbol] id a widget id
    # @return always true
    def WJ_Validate_True(id)
      true
    end

    # Call the validation functions for a list of widgets.
    # Widgets with an unspecified function are assumed to be valid.
    # Uses a global Widgets map. {#widget_def}
    # @param [Array] widgets which widgets to validate
    # @return	true if all widgets are ok
    def WJ_Validate(widgets)
      widgets = deep_copy(widgets)
      ok = true
      Builtins.foreach(widgets) do |id|
        if ok
          if Ops.is_symbol?(id)
            id_sym = Convert.to_symbol(id)
            w_def = Ops.get_map(@Widgets, id)
            if w_def == nil
              # report as the caller
              Builtins.y2error(1, "WJ: Missing widget definition for %1", id)
              ok = false
            else
              validate = Convert.convert(
                Ops.get(
                  w_def,
                  "validate",
                  fun_ref(method(:WJ_Validate_True), "boolean (symbol)")
                ),
                :from => "any",
                :to   => "boolean (symbol)"
              )
              ok = validate.call(id_sym)
            end
          else
            ok = false
          end
        else
          next #break
        end
      end
      ok
    end

    # Set a variable acording to widget value
    # This is an error reporting  fallback if the real function was not defined
    # @param [Symbol] id widget id
    def WJ_Set_Missing(id)
      # report as the caller
      Builtins.y2error(1, "WJ: Missing Set definition for %1", id)

      nil
    end

    # Call the "set" functions for a list of widgets
    # to commit the UI values to a module.
    # Uses a global Widgets map. {#widget_def}
    # @param [Array] widgets which widgets to commit
    def WJ_Set(widgets)
      widgets = deep_copy(widgets)
      Builtins.foreach(widgets) do |id|
        if Ops.is_symbol?(id)
          id_sym = Convert.to_symbol(id)

          set_it = Convert.convert(
            Ops.get(
              @Widgets,
              [id_sym, "set"],
              fun_ref(method(:WJ_Set_Missing), "void (symbol)")
            ),
            :from => "any",
            :to   => "void (symbol)"
          )
          set_it.call(id_sym)
        end
      end

      nil
    end


    # ----------------------------------------------------------------
    # Layout
    # Helpers for frequently used layout idioms

    # Make a RadioButtonGroup containing Left aligned widgets
    # in a VBox that has VSpacing (0.2) as top/bottom padding.
    # @param [Symbol] g_id	group id
    # @param [Array<Yast::Term>] rbs	a list of widgets, usually RadioButtons
    # @return	widget
    def RadioButtonVBox(g_id, rbs)
      rbs = deep_copy(rbs)
      spacing = VSpacing(0.2)
      rb_vbox = VBox(spacing)
      Builtins.foreach(rbs) do |rb|
        left_rb = Left(rb)
        rb_vbox = Builtins.add(rb_vbox, left_rb)
      end
      rb_vbox = Builtins.add(rb_vbox, spacing)

      RadioButtonGroup(Id(g_id), rb_vbox)
    end
  end
end
