require 'spec_helper'
require 'rest_spec_helper'
require 'rhc/commands/scp'

describe RHC::Commands::Scp do
  let!(:rest_client){ MockRestClient.new }
  let!(:config){ user_config }
  before{ RHC::Config.stub(:home_dir).and_return('/home/mock_user') }
  before{ Kernel.stub(:exec).and_raise(RuntimeError) }

  describe 'scp default' do
    context 'scp' do
      let(:arguments) { ['scp'] }
      it { run_output.should match('Usage:') }
    end
  end

  describe 'scp with invalid option' do
    let (:arguments) {['app', 'scp', 'app1', 'invalid_command', 'file.txt', 'app-root/data']}

    context 'when run' do
      before(:each) do
        @domain = rest_client.add_domain("mockdomain")
        @domain.add_application("app1", "mock_type")
      end
      it { run_output.should match("'invalid_command' is not a valid argument for this command.  Please use upload or download.") }
    end
  end

  describe 'local file or path does not exist' do
    let (:arguments) {['app', 'scp', 'app1', 'upload', 'file.txt', 'app-root/data']}

    context 'when run' do
      before(:each) do
        @domain = rest_client.add_domain("mockdomain")
        @domain.add_application("app1", "mock_type")
        File.should_receive(:exist?).with("file.txt").once.and_return(false)
        File.should_receive(:exist?).with("git").at_least(1).and_return(true)
      end
      it { run_output.should match("Local file, file_path, or directory could not be found.") }
    end
  end

  describe 'scp connections' do
    let (:arguments) {['app', 'scp', 'app1', 'upload', 'file.txt', 'app-root/data']}

    context 'connection refused' do
      before(:each) do
        @domain = rest_client.add_domain("mockdomain")
        @domain.add_application("app1", "mock_type")
        File.should_receive(:exist?).with("file.txt").once.and_return(true)
        File.should_receive(:exist?).with("git").at_least(1).and_return(true)
        Net::SCP.should_receive("upload!".to_sym).with("127.0.0.1", "fakeuuidfortestsapp1","file.txt","app-root/data").and_raise(Errno::ECONNREFUSED)
      end
      it { run_output.should match("The server fakeuuidfortestsapp1 refused a connection with user 127.0.0.1.  The application may be unavailable.") }
    end

    context 'socket error' do
      before(:each) do
        @domain = rest_client.add_domain("mockdomain")
        @domain.add_application("app1", "mock_type")
        File.should_receive(:exist?).with("file.txt").once.and_return(true)
        File.should_receive(:exist?).with("git").at_least(1).and_return(true)
        Net::SCP.should_receive("upload!".to_sym).with("127.0.0.1", "fakeuuidfortestsapp1","file.txt","app-root/data").and_raise(SocketError)
      end
      it { run_output.should match("The connection to 127.0.0.1 failed: SocketError") }
    end


    context 'authentication error' do
      before(:each) do
        @domain = rest_client.add_domain("mockdomain")
        @domain.add_application("app1", "mock_type")
        File.should_receive(:exist?).with("file.txt").once.and_return(true)
        File.should_receive(:exist?).with("git").at_least(1).and_return(true)
        Net::SCP.should_receive("upload!".to_sym).with("127.0.0.1", "fakeuuidfortestsapp1","file.txt","app-root/data").and_raise(Net::SSH::AuthenticationFailed)
      end
      it { run_output.should match("Authentication to server 127.0.0.1 with user fakeuuidfortestsapp1 failed") }
    end

    context 'unknown error' do
      before(:each) do
        @domain = rest_client.add_domain("mockdomain")
        @domain.add_application("app1", "mock_type")
        File.should_receive(:exist?).with("file.txt").once.and_return(true)
        File.should_receive(:exist?).with("git").at_least(1).and_return(true)
        Net::SCP.should_receive("upload!".to_sym).with("127.0.0.1", "fakeuuidfortestsapp1","file.txt","app-root/data").and_raise(Net::SCP::Error.new("SCP error message"))
      end
      it { run_output.should match("An unknown error occurred: SCP error message") }
    end
  end

  describe 'scp upload with custom ssh executable specified' do
    ssh_path = '/usr/bin/ssh'
    let (:arguments) {['app', 'scp', 'app1', 'upload', 'file.txt', 'app-root/data']}

    before(:each) do
      base_config { |c, d| d.add 'ssh', ssh_path }
    end

    context 'on windows' do
      before(:each) do
        @domain = rest_client.add_domain("mockdomain")
        @domain.add_application("app1", "mock_type")
        File.should_receive(:exist?).with("file.txt").once.and_return(true)
        File.should_receive(:exist?).with("git").at_least(1).and_return(true)
      end

      it 'should report a helpful warning message' do
        subject.class.any_instance.should_receive(:windows?).and_return(true)
        expect { run }.to exit_with_code(1)
        expect { run_output.should match(/User specified a ssh executable.*On Windows, file transfers.*cannot be used with this command/) }
      end
    end

    context 'on linux' do
      before(:each) do
        @domain = rest_client.add_domain("mockdomain")
        @domain.add_application("app1", "mock_type")
        File.should_receive(:exist?).with("file.txt").once.and_return(true)
        File.should_receive(:exist?).with("git").at_least(1).and_return(true)
      end

      it 'should report an scp upload command when uploading' do
        subject.class.any_instance.should_receive(:windows?).and_return(false)
        expect { run }.to exit_with_code(1)
        expect { run_output.should match(/scp -S #{ssh_path} file\.txt '.*@.*'/) }
      end
    end
  end

  describe 'scp download with custom ssh executable specified' do
    ssh_path = '/usr/bin/ssh'
    let (:arguments) {['app', 'scp', 'app1', 'download', '.', '~/app-root/data/file.txt']}

    before(:each) do
      base_config { |c, d| d.add 'ssh', ssh_path }
    end

    context 'on linux' do
      before(:each) do
        @domain = rest_client.add_domain("mockdomain")
        @domain.add_application("app1", "mock_type")
        File.should_receive(:exist?).with('.').once.and_return(true)
        File.should_receive(:exist?).with("git").at_least(1).and_return(true)
      end

      it 'should report an scp download command when downloading' do
        subject.class.any_instance.should_receive(:windows?).and_return(false)
        expect { run }.to exit_with_code(1)
        expect { run_output.should match(/can usually be used.*scp -S #{ssh_path} '.*@.*' .\/file\.txt/) }
      end
    end
  end

end
