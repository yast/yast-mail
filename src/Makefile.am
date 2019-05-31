# Sources for mail

module_DATA = \
  modules/Mail.rb 

client_DATA = \
  clients/mail.rb \
  clients/mail_auto.rb

yncludedir = @yncludedir@/mail
ynclude_DATA = \
  include/mail/widgets.rb \
  include/mail/ui.rb \
  include/mail/wj.rb \
  include/mail/helps.rb

scrconf_DATA = \
  scrconf/etc_imapd_conf.scr \
  scrconf/mail_p_canonical.scr \
  scrconf/mail_maincf.scr \
  scrconf/mail_saslpasswd.scr \
  scrconf/mail_s_generics.scr \
  scrconf/mail_fetchmail.scr \
  scrconf/cfg_fetchmail.scr \
  scrconf/cfg_sendmail.scr \
  scrconf/mail_p_auth.scr \
  scrconf/mail_p_virtual.scr \
  scrconf/mail_ldaptable.scr \
  scrconf/mail_aliases.scr \
  scrconf/mail_s_virtuser.scr \
  scrconf/cfg_amavis.scr \
  scrconf/mail_s_auth.scr \
  scrconf/cfg_postfix.scr

agent_SCRIPTS = \
  servers_non_y2/ag_mail_ldaptable \
  servers_non_y2/ag_fetchmailrc \
  servers_non_y2/MasterCFParser.pm \
  servers_non_y2/setup_dkim_verifying.pl \
  servers_non_y2/ag_mailtable \
  servers_non_y2/ag_mailconfig \
  servers_non_y2/ag_smtp_auth

schemafilesdir = $(schemadir)/autoyast/rnc
schemafiles_DATA = \
  autoyast-rnc/mail.rnc

desktop_DATA = \
  desktop/org.openSUSE.YaST.Mail.desktop

fillup_DATA = \
  fillup/sysconfig.mail

symbolicdir = @icondir@/hicolor/symbolic/apps
symbolic_DATA = \
  icons/hicolor/symbolic/apps/yast-mail-symbolic.svg
scalabledir = @icondir@/hicolor/scalable/apps
scalable_DATA = \
  icons/hicolor/scalable/apps/yast-mail.svg

EXTRA_DIST = $(module_DATA) $(module1_DATA) $(client_DATA) $(ynclude_DATA) $(scrconf_DATA) $(agent_SCRIPTS) $(schemafiles_DATA) $(desktop_DATA) $(fillup_DATA) $(symbolic_DATA) $(scalable_DATA)

include $(top_srcdir)/Makefile.am.common
