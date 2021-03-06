require 'socket'
require 'base64'
class XChannel::UNIXSocket
  NULL_BYTE = "\x00"

  #
  # @param [#dump, #load] serializer
  #   A serializer (eg Marshal, JSON, YAML)
  #
  # @return [XChannel::UNIXSocket]
  #
  def initialize(serializer = Marshal)
    @serializer = serializer
    @last_msg = nil
    @reader, @writer = ::UNIXSocket.pair :STREAM
  end

  #
  # @return [Boolean]
  #   Returns true when the channel is closed.
  #
  def closed?
    @reader.closed? and @writer.closed?
  end

  #
  # @raise [IOError]
  #   An IOError is raised if the channel is already closed.
  #
  # @return [Boolean]
  #   Returns true when the channel is closed.
  #
  def close
    if closed?
      raise IOError, 'closed channel'
    else
      @reader.close
      @writer.close
      true
    end
  end

  #
  # Performs a blocking write.
  #
  # @raise [IOError]
  #   (see #send!)
  #
  # @param [Object] object
  #   Object to write to channel.
  #
  def send(object)
    send!(object, nil)
  end
  alias_method :write, :send

  #
  # Performs a write with a timeout.
  #
  # @param [Object] object
  #   Object to write to channel.
  #
  # @param [Float, Fixnum] timeout
  #   Number of seconds to wait.
  #
  # @raise [IOError]
  #   An IOError is raised when the channel is closed.
  #
  # @raise [XChannel::TimeoutError]
  #   XChannel::TimeoutError is raised when the write doesn't complete within the timeout.
  #
  def send!(object, timeout = 0.1)
    if @writer.closed?
      raise IOError, 'closed channel'
    end
    _, writable, _ = IO.select nil, [@writer], nil, timeout
    if writable
      msg = @serializer.dump(object)
      writable[0].syswrite "#{Base64.strict_encode64(msg)}#{NULL_BYTE}"
    else
      raise XChannel::TimeoutError, "write timed out after waiting #{timeout} seconds"
    end
  end
  alias_method :write!, :send!

  #
  # Performs a blocking read.
  #
  # @raise
  #   (see XChannel::UNIXSocket#recv!)
  #
  # @return [Object]
  #
  def recv
    recv!(nil)
  end
  alias_method :read, :recv

  #
  # Performs a read with a timeout.
  #
  # @param [Float, Fixnum] timeout
  #   Number of seconds to wait before raising an exception.
  #
  # @raise [IOError]
  #   An IOError is raised when the channel is closed.
  #
  # @raise [XChannel::TimeoutError]
  #   XChannel::TimeoutError is raised when the read doesn't complete within the specified timeout.
  #
  # @return [Object]
  #
  def recv!(timeout = 0.1)
    if @reader.closed?
      raise IOError, 'closed channel'
    end
    readable, _ = IO.select [@reader], nil, nil, timeout
    if readable
      base64 = readable[0].readline(NULL_BYTE).chomp(NULL_BYTE)
      @last_msg = @serializer.load Base64.strict_decode64(base64)
    else
      raise XChannel::TimeoutError, "read timed out after waiting #{timeout} seconds"
    end
  end
  alias_method :read!, :recv!

  #
  # Reads from a channel until there are no messages left, and
  # then returns the last read message.
  #
  # @return [Object]
  #
  def last_msg
    @last_msg = recv while readable?
    @last_msg
  end

  #
  # @return [Boolean]
  #   Returns true when the channel can be read from.
  #
  def readable?
    if closed?
      false
    else
      readable, _ = IO.select [@reader], nil, nil, 0
      !! readable
    end
  end
end
