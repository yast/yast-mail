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

Yast.import "MailTable"
Yast.import "MailAliases"

describe Yast::MailAliases do
  describe ".mergeTables" do
    let(:old1) do
      [
        {
          "comment" => " Basic system aliases that MUST be present.\n",
          "value"   => "root",
          "key"     => "postmaster"
        },
        { "comment" => "", "value" => "postmaster", "key" => "mailer-daemon" },
        { "comment" => " amavis\n", "value" => "root", "key" => "virusalert" },
        {
          "comment" => " General redirections for pseudo accounts in /etc/passwd.\n",
          "value"   => "root",
          "key"     => "administrator"
        },
        { "comment" => "", "value" => "root", "key" => "daemon" },
        { "comment" => "", "value" => "root", "key" => "nobody" },
        {
          "comment" => " \"bin\" used to be in /etc/passwd\n",
          "value"   => "root",
          "key"     => "bin"
        },
        {
          "comment" => " Further well-known aliases for dns/news/ftp/mail/fax/web/gnats.\n",
          "value"   => "news",
          "key"     => "newsadm"
        },
        { "comment" => "", "value" => "news", "key" => "newsadmin" },
        { "comment" => "", "value" => "news", "key" => "usenet" }
      ]
    end

    let(:new1) do
      [
        { "key" => "root", "value" => "auser", "comment" => " I am r00t!" },
        { "key" => "B.User", "value" => "buser", "comment" => " blah" },
        { "key" => "usenet", "value" => "root", "comment" => " direct" },
        { "key" => "A.User", "value" => "auser", "comment" => "" },
        { "key" => "newsadmin", "value" => "root", "comment" => " direct" }
      ]
    end

    let(:merged) do
      old1[0..7] + [
        { "comment" => " direct", "key" => "newsadmin", "value" => "root" },
        { "comment" => " direct", "key" => "usenet", "value" => "root" },
        { "comment" => " I am r00t!", "key" => "root", "value" => "auser" },
        { "comment" => " blah", "key" => "B.User", "value" => "buser" },
        { "comment" => "", "key" => "A.User", "value" => "auser" }
      ]
    end

    it "returns a merged table" do
      expect(described_class.mergeTables(new1, old1)).to eq merged
    end

    context "when the first table is empty" do
      let(:new1) { [] }

      it "returns the second table" do
        expect(described_class.mergeTables(new1, old1)).to eq old1
      end
    end

    context "when the second table is empty" do
      let(:old1) { [] }

      it "returns the first table" do
        expect(described_class.mergeTables(new1, old1)).to eq new1
      end
    end

    context "when both tables are empty" do
      let(:old1) { [] }
      let(:new1) { [] }

      it "returns an empty table" do
        expect(described_class.mergeTables(new1, old1)).to eq []
      end
    end
  end

  # NOTE:
  #   This is a highly simplified version of the old rootalias.rb test.
  #   To be a real substitute we should test the effect of #SetRootAlias
  #   as well.
  describe ".GetRootAlias" do
    before do
      Yast::MailTable.SetFileName("aliases", "#{DATA_PATH}/aliases")
    end

    it "returns the value from the aliases file" do
      expect(described_class.GetRootAlias).to eq "leaf"
    end
  end
end
