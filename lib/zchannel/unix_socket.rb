require 'socket'
class ZChannel::UNIXSocket
  SEP = '_$_'  if respond_to? :private_constant

  #
  # @param [#dump,#load] serializer
  #   An object who implements `.dump` and `.load` methods
  #
  # @return [ZChannel::UNIXSocket]
  #
  def initialize(serializer)
    @serializer = serializer
    @last_msg = nil
    @reader, @writer = ::UNIXSocket.pair :STREAM
  end

  #
  # @return [Boolean]
  #   Returns true when a channel is closed
  #
  def closed?
    @reader.closed? and @writer.closed?
  end

  #
  # Close the channel
  #
  # @raise [IOError]
  #   When a channel is already closed
  #
  # @return [Boolean]
  #   Returns true on success
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
  # @raise [IOError]
  #   (see #send!)
  #
  # @param [Object] object
  #   An object to add to a channel
  #
  def send(object)
    send!(object, nil)
  end
  alias_method :write, :send

  #
  # @param
  #   (see ZChannel::UNIXSocket#send)
  #
  # @param [Fixnum] timeout
  #   Number of seconds to wait before raising an exception
  #
  # @raise [IOError]
  #   When channel is closed
  #
  # @raise [ZChannel::TimeoutError]
  #   When a write doesn't finish within the timeout
  #
  def send!(object, timeout = 0.1)
    if @writer.closed?
      raise IOError, 'closed channel'
    end
    _, writable, _ = IO.select nil, [@writer], nil, timeout
    if writable
      msg = @serializer.dump(object)
      writable[0].syswrite "#{msg}#{SEP}"
    else
      raise ZChannel::TimeoutError, "timeout, waited #{timeout} seconds"
    end
  end
  alias_method :write!, :send!

  #
  # Perform a blocking read
  #
  # @raise
  #   (see ZChannel::UNIXSocket#recv)
  #
  # @return [Object]
  #
  def recv
    recv!(nil)
  end
  alias_method :read, :recv

  #
  # Perform a read with a timeout
  #
  # @param [Fixnum] timeout
  #   Number of seconds to wait before raising an exception
  #
  # @raise [IOError]
  #   When channel is closed
  #
  # @raise [ZChannel::TimeoutError]
  #   When a read doesn't finish within the timeout
  #
  # @return [Object]
  #
  def recv!(timeout = 0.1)
    if @reader.closed?
      raise IOError, 'closed channel'
    end
    readable, _ = IO.select [@reader], nil, nil, timeout
    if readable
      msg = readable[0].readline(SEP).chomp SEP
      @last_msg = @serializer.load msg
    else
      raise ZChannel::TimeoutError, "timeout, waited #{timeout} seconds"
    end
  end
  alias_method :read!, :recv!

  #
  # @return [Object]
  #   Reads from a channel until there are no messages left, and
  #   then returns the last read message.
  #
  def last_msg
    @last_msg = recv while readable?
    @last_msg
  end

  #
  # @return [Boolean]
  #   Returns true when a channel has messages waiting to be read.
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
