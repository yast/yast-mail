# Sources for mail

module_DATA = \
  modules/MailServer.rb \
  modules/Mail.rb \
  modules/MailServerLDAP.pm

module1dir = @moduledir@/YaPI
module1_DATA = \
  modules/YaPI/MailServer.pm

client_DATA = \
  clients/mail.rb \
  clients/mail-server.rb \
  clients/mail-server_ldap-setup.rb \
  clients/mail-server_proposal.rb \
  clients/mail-advanced.rb \
  clients/mail-standard.rb \
  clients/mail-server_auto.rb \
  clients/mail_auto.rb

yncludedir = @yncludedir@/mail
ynclude_DATA = \
  include/mail/widgets.rb \
  include/mail/mail-server_dialogs.rb \
  include/mail/mail-server_helps.rb \
  include/mail/mail-server_complex.rb \
  include/mail/ui.rb \
  include/mail/mail-server_wizards.rb \
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
  scrconf/cfg_mail.scr \
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
  desktop/mail.desktop

fillup_DATA = \
  fillup/sysconfig.mail

EXTRA_DIST = $(module_DATA) $(module1_DATA) $(client_DATA) $(ynclude_DATA) $(scrconf_DATA) $(agent_SCRIPTS) $(schemafiles_DATA) $(desktop_DATA) $(fillup_DATA)

include $(top_srcdir)/Makefile.am.common
