require 'rspec/core/drb'
require 'rspec/core/bisect/coordinator'
require 'rspec/core/project_initializer'

module RSpec::Core
  RSpec.describe Invocations do
    let(:configuration_options) { instance_double(ConfigurationOptions) }
    let(:err) { StringIO.new }
    let(:out) { StringIO.new }

    def run_invocation
      subject.call(configuration_options, err, out)
    end

    describe Invocations::InitializeProject do
      it "initializes a project and returns a 0 exit code" do
        project_init = instance_double(ProjectInitializer, :run => nil)
        allow(ProjectInitializer).to receive_messages(:new => project_init)

        exit_code = run_invocation

        expect(project_init).to have_received(:run)
        expect(exit_code).to eq(0)
      end
    end

    describe Invocations::DRbWithFallback do
      context 'when a DRb server is running' do
        it "builds a DRbRunner and runs the specs" do
          drb_proxy = instance_double(RSpec::Core::DRbRunner, :run => 0)
          allow(RSpec::Core::DRbRunner).to receive(:new).and_return(drb_proxy)

          exit_code = run_invocation

          expect(drb_proxy).to have_received(:run).with(err, out)
          expect(exit_code).to eq(0)
        end
      end

      context 'when a DRb server is not running' do
        let(:runner) { instance_double(RSpec::Core::Runner, :run => 0) }

        before(:each) do
          allow(RSpec::Core::Runner).to receive(:new).and_return(runner)
          allow(RSpec::Core::DRbRunner).to receive(:new).and_raise(DRb::DRbConnError)
        end

        it "outputs a message" do
          run_invocation

          expect(err.string).to include(
            "No DRb server is running. Running in local process instead ..."
          )
        end

        it "builds a runner instance and runs the specs" do
          run_invocation

          expect(RSpec::Core::Runner).to have_received(:new).with(configuration_options)
          expect(runner).to have_received(:run).with(err, out)
        end

        if RSpec::Support::RubyFeatures.supports_exception_cause?
          it "prevents the DRb error from being listed as the cause of expectation failures" do
            allow(RSpec::Core::Runner).to receive(:new) do |configuration_options|
              raise RSpec::Expectations::ExpectationNotMetError
            end

            expect {
              run_invocation
            }.to raise_error(RSpec::Expectations::ExpectationNotMetError) do |e|
              expect(e.cause).to be_nil
            end
          end
        end
      end
    end

    describe Invocations::Bisect do
      let(:bisect) { nil }
      let(:options) { { :bisect => bisect } }
      let(:args) { double(:args) }
      let(:success) { true }

      before do
        allow(configuration_options).to receive_messages(:args => args, :options => options)
        allow(RSpec::Core::Bisect::Coordinator).to receive(:bisect_with).and_return(success)
      end

      it "starts the bisection coordinator" do
        run_invocation

        expect(RSpec::Core::Bisect::Coordinator).to have_received(:bisect_with).with(
          args,
          RSpec.configuration,
          Formatters::BisectProgressFormatter
        )
      end

      context "when the bisection is successful" do
        it "returns 0" do
          exit_code = run_invocation

          expect(exit_code).to eq(0)
        end
      end

      context "when the bisection is unsuccessful" do
        let(:success) { false }

        it "returns 1" do
          exit_code = run_invocation

          expect(exit_code).to eq(1)
        end
      end

      context "and the verbose option is specified" do
        let(:bisect) { "verbose" }

        it "starts the bisection coordinator with the debug formatter" do
          run_invocation

          expect(RSpec::Core::Bisect::Coordinator).to have_received(:bisect_with).with(
            args,
            RSpec.configuration,
            Formatters::BisectDebugFormatter
          )
        end
      end
    end

    describe Invocations::PrintVersion do
      it "prints the version and returns a zero exit code" do

        exit_code = run_invocation

        expect(exit_code).to eq(0)
        expect(out.string).to include("#{RSpec::Core::Version::STRING}\n")
      end
    end

    describe Invocations::PrintHelp do
      let(:parser) { instance_double(OptionParser) }
      let(:invalid_options) { %w[ -d ] }

      subject { described_class.new(parser, invalid_options) }

      before do
        allow(parser).to receive(:to_s).and_return(<<-EOS)
        -d
        --bisect[=verbose]           Repeatedly runs the suite in order...
        EOS
      end

      it "prints the CLI options and returns a zero exit code" do
        exit_code = run_invocation

        expect(exit_code).to eq(0)
        expect(out.string).to include("--bisect")
      end

      it "won't display invalid options in the help output" do
        useless_lines = /^\s*-d\s*$\n/

        run_invocation

        expect(out.string).to_not match(useless_lines)
      end
    end
  end
end
