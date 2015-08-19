require 'spec_helper'

describe "ROM::PluginRegistry" do
  subject(:env) { setup.finalize }

  let(:setup) { ROM.setup(:memory) }

  before do
    Test::EnvironmentPlugin = Module.new
    Test::CommandPlugin     = Module.new
    Test::MapperPlugin      = Module.new
    Test::RelationPlugin    = Module.new do
      def plugged_in
        "a relation"
      end
    end

    ROM.plugins do
      register :registration, Test::EnvironmentPlugin, type: :environment
      register :publisher,    Test::CommandPlugin,     type: :command
      register :pager,        Test::RelationPlugin,    type: :relation
      register :translater,   Test::MapperPlugin,      type: :mapper
    end
  end

  around do |example|
    orig_plugins = ROM.plugin_registry
    example.run
    ROM.instance_variable_set('@plugin_registry', orig_plugins)
  end

  it "makes environment plugins available" do
    expect(ROM.plugin_registry.environment[:registration].mod).to eq Test::EnvironmentPlugin
  end

  it "includes relation plugins" do
    setup.relation(:users) do
      use :pager
    end

    expect(env.relation(:users).plugged_in).to eq "a relation"
  end

  it "makes command plugins available" do
    setup.relation(:users)

    Class.new(ROM::Commands::Create[:memory]) do
      relation :users
      register_as :create
      use :publisher
    end

    expect(env.command(:users).create).to be_kind_of Test::CommandPlugin
  end

  it "inclues plugins in mappers" do
    setup.relation(:users)

    Class.new(ROM::Mapper) do
      relation :users
      register_as :translator
      use :translater
    end

    expect(env.mappers[:users][:translator]).to be_kind_of Test::MapperPlugin
  end

  it "restricts plugins to defined type" do
    expect {
      setup.relation(:users) do
        use :publisher
      end
    }.to raise_error ROM::UnknownPluginError
  end

  it "allows definition of adapter restricted plugins" do
    Test::LazyPlugin = Module.new do
      def lazy?
        true
      end
    end

    ROM.plugins do
      adapter :memory do
        register :lazy, Test::LazyPlugin, type: :relation
      end
    end

    setup.relation(:users) do
      use :lazy
    end

    expect(env.relation(:users)).to be_lazy
  end

  it "respects adapter restrictions" do
    Test::LazyPlugin = Module.new
    Test::LazyMemoryPlugin = Module.new
    Test::LazySQLPlugin = Module.new

    ROM.plugins do
      register :lazy, Test::LazyPlugin, type: :command

      adapter :memory do
        register :lazy_command, Test::LazyMemoryPlugin, type: :command
      end

      adapter :sql do
        register :lazy, Test::LazySQLPlugin, type: :command
      end
    end

    setup.relation(:users)

    Class.new(ROM::Commands::Create[:memory]) do
      relation :users
      register_as :create
      use :lazy
    end

    Class.new(ROM::Commands::Update[:memory]) do
      relation :users
      register_as :update
      use :lazy_command
    end

    expect(env.command(:users).create).not_to be_kind_of Test::LazySQLPlugin
    expect(env.command(:users).create).to be_kind_of Test::LazyPlugin
    expect(env.command(:users).update).to be_kind_of Test::LazyMemoryPlugin
  end
end