#!/usr/bin/env rspec
# Copyright (c) [2020] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com.

require_relative "test_helper"

Yast.import "Progress"
Yast.import "Mail"
Yast.import "MailTable"

describe Yast::Mail do
  def expect_sysconfig_read(route, value)
    expect(Yast::SCR).to receive(:Read).with(path(".sysconfig.#{route}")).and_return value
  end

  def allow_read(route, value)
    allow(Yast::SCR).to receive(:Read).with(path(route)).and_return value
  end

  let(:must_abort) { proc { false } }
  let(:firewalld) { double("Firewalld", read: true) }

  before do
    allow(Yast::PackageSystem).to receive(:Installed) do |package|
      package == mail_system
    end

    Yast::MailTable.SetFileName("aliases", "#{DATA_PATH}/aliases")
    allow(Yast::MailTable).to receive(:Read).and_call_original

    Yast::Progress.off

    allow(Y2Firewall::Firewalld).to receive(:instance).and_return firewalld
    allow(Yast::Service).to receive(:Enabled).with("fetchmail").and_return false

    allow_read(".sysconfig.mail.MAIL_CREATE_CONFIG", "yes")
    allow_read(".sysconfig.mail.SMTPD_LISTEN_REMOTE", "yes")
    allow_read(".sysconfig.amavis.USE_AMAVIS", "no")
    allow_read(".sysconfig.mail.FROM_HEADER", "foo.test")
    allow_read(".mail.fetchmail.accounts", [])

    allow(Yast::SCR).to receive(:Execute).with(path(".target.bash_output"), "/usr/bin/id --user")
      .and_return("stdout" => "0\n")
  end

  context "when sendmail is installed" do
    let(:mail_system) { "sendmail" }

    before do
      Yast::MailTable.SetFileName("sendmail.generics", "#{DATA_PATH}/empty")
      Yast::MailTable.SetFileName("sendmail.virtuser", "#{DATA_PATH}/empty")
    end

    describe ".Read" do
      it "reads the sendmail configuration" do
        expect_sysconfig_read("sendmail.SENDMAIL_NOCANONIFY", "no")
        expect_sysconfig_read("sendmail.SENDMAIL_EXPENSIVE", "no")
        expect_sysconfig_read("sendmail.SENDMAIL_LOCALHOST", "")
        expect_sysconfig_read("sendmail.SENDMAIL_SMARTHOST", "")
        expect_sysconfig_read("sendmail.MASQUERADE_DOMAINS", "")

        expect(Yast::MailTable).to receive(:Read).with("sendmail.generics").and_call_original
        expect(Yast::MailTable).to receive(:Read).with("sendmail.virtuser").and_call_original

        expect(Yast::SCR).to receive(:Read).with(path(".mail.sendmail.auth.accounts"))
          .and_return("more" => 1, "password" => "p", "server" => "s", "user" => "u")

        expect_sysconfig_read("sendmail.SMTP_AUTH_MECHANISMS", "")

        described_class.Read(must_abort)
      end
    end

    describe ".Write" do
      before do
        # To make this work in the same way than the old testsuite, let's
        # execute Read first (with all the needed mocks)

        allow_read(".sysconfig.sendmail.SENDMAIL_NOCANONIFY", "no")
        allow_read(".sysconfig.sendmail.SENDMAIL_EXPENSIVE", "no")
        allow_read(".sysconfig.sendmail.SENDMAIL_LOCALHOST", "")
        allow_read(".sysconfig.sendmail.SENDMAIL_SMARTHOST", "")
        allow_read(".sysconfig.sendmail.MASQUERADE_DOMAINS", "")
        allow_read(
          ".mail.sendmail.auth.accounts",
          "more" => 1, "password" => "p", "server" => "s", "user" => "u"
        )
        allow_read(".sysconfig.sendmail.SMTP_AUTH_MECHANISMS", "")

        described_class.Read(must_abort)
        # Now we are ready to call Write with a known state

        # Let's mock now the calls executed by Write itself
        allow(firewalld).to receive(:write_only)
        allow_read(".sysconfig.sendmail.SENDMAIL_ARGS", "-L sendmail -Am -bd -q30m -om")
      end

      def expect_write(route, value)
        expect(Yast::SCR).to receive(:Write).with(path(route), value)
      end

      it "writes the sendmail configuration and adjusts all running services" do
        expect_write(".sysconfig.mail.MAIL_CREATE_CONFIG", "yes")
        expect_write(".sysconfig.mail.SMTPD_LISTEN_REMOTE", "yes")
        expect_write(".sysconfig.mail.FROM_HEADER", "foo.test")
        expect_write(".sysconfig.mail", nil)
        expect_write(".sysconfig.sendmail.SENDMAIL_NOCANONIFY", "no")
        expect_write(".sysconfig.sendmail.SENDMAIL_EXPENSIVE", "no")
        expect_write(".sysconfig.sendmail.SENDMAIL_LOCALHOST", "")
        expect_write(".sysconfig.sendmail.SENDMAIL_SMARTHOST", "")
        expect_write(".sysconfig.sendmail.MASQUERADE_DOMAINS", "")
        expect_write(".sysconfig.sendmail", nil)
        expect_write(".sysconfig.amavis.USE_AMAVIS", "no")
        expect_write(".sysconfig.amavis.USE_DKIM", "no")
        expect_write(".sysconfig.amavis", nil)
        expect_write(".mail.sendmail.auth.accounts", nil)
        expect_write(".mail.sendmail.auth", nil)

        expect(Yast::SCR).to receive(:Execute).with(
          path(".target.bash"),
          /test -e .*novell.postfix-check-mail-queue.* rm .*novell.postfix-check-mail-queue/
        )

        expect(Yast::MailAliases).to receive(:WriteAliases).and_return true
        expect(Yast::MailTable).to receive(:Write).with("sendmail.virtuser", anything)
        expect(Yast::MailTable).to receive(:Write).with("sendmail.generics", anything)

        expect(Yast::Service).to receive(:Enable).with "sendmail"
        expect(Yast::Service).to receive(:Adjust).with("amavis", anything).twice
        expect(Yast::Service).to receive(:Adjust).with("freshclam", anything)
        expect(Yast::Service).to receive(:Adjust).with("clamd", anything)
        expect(Yast::Service).to receive(:Stop).with "amavis"
        expect(Yast::Service).to receive(:Stop).with "fetchmail"
        expect(Yast::Service).to receive(:Restart).with("sendmail").and_return true
        expect(firewalld).to receive(:reload)

        described_class.Write(must_abort)
      end
    end
  end

  context "when postfix is installed" do
    let(:mail_system) { "postfix" }

    before do
      Yast::MailTable.SetFileName("postfix.sendercanonical", "#{DATA_PATH}/empty")
      Yast::MailTable.SetFileName("postfix.virtual", "#{DATA_PATH}/empty")

      allow(Yast::Service).to receive(:Enabled).with("postfix").and_return false
    end

    it "reads the postfix configuration" do
      expect_sysconfig_read("postfix.POSTFIX_NODNS", "no")
      expect_sysconfig_read("postfix.POSTFIX_DIALUP", "no")
      expect_sysconfig_read("postfix.POSTFIX_LOCALDOMAINS", "")
      expect_sysconfig_read("postfix.POSTFIX_SMTP_TLS_CLIENT", "")
      expect_sysconfig_read("postfix.POSTFIX_RELAYHOST", "")
      expect_sysconfig_read("postfix.POSTFIX_MDA", "local")
      expect_sysconfig_read("postfix.POSTFIX_MASQUERADE_DOMAIN", "")

      expect(Yast::MailTable).to receive(:Read).with("postfix.sendercanonical").and_call_original
      expect(Yast::MailTable).to receive(:Read).with("postfix.virtual").and_call_original

      expect(Yast::SCR).to receive(:Read).with(path(".mail.postfix.auth.accounts"))
        .and_return("more" => 1, "password" => "p", "server" => "s", "user" => "u")

      described_class.Read(must_abort)
    end
  end
end
