use "http"

actor Main
  let _env: Env

  new create(env: Env) =>
    _env = env

    let url = "https://example.com"
    let method = "GET"

    try
      let client = HTTPClient(env.root as AmbientAuth)
      let url' = URL.build(url)?
      let request = Payload.request(method, url')

      let dumpMaker = recover val NotifyFactory.create(this) end

      // Send GET Request
      client(consume request, dumpMaker)?
    end

  be cancelled() =>
    """
    Process cancellation from the server end.
    """
    _env.out.print("-- response cancelled --")

  be have_response(response: Payload val) =>
    """
    Process return the the response message.
    """
    if response.status == 0 then
      _env.out.print("Failed")
      return
    end

    // Print the status and method
    _env.out.print(
      "Response " +
      response.status.string() + " " +
      response.method)

    // Print all the headers
    for (k, v) in response.headers().pairs() do
      _env.out.print(k + ": " + v)
    end

    _env.out.print("")

    // Print the body if there is any.  This will fail in Chunked or
    // Stream transfer modes.
    try
      let body = response.body()?
      for piece in body.values() do
        _env.out.write(piece)
      end
    end

  be have_body(data: ByteSeq val)
    =>
    """
    Some additional response data.
    """
    _env.out.write(data)

  be finished() =>
    """
    End of the response data.
    """
    _env.out.print("-- end of body --")

class NotifyFactory is HandlerFactory
  """
  Create instances of our simple Receive Handler.
  """
  let _main: Main

  new iso create(main': Main) =>
    _main = main'

  fun apply(session: HTTPSession): HTTPHandler ref^ =>
    HttpNotify.create(_main, session)

class HttpNotify is HTTPHandler
  """
  Handle the arrival of responses from the HTTP server.  These methods are
  called within the context of the HTTPSession actor.
  """
  let _main: Main
  let _session: HTTPSession

  new ref create(main': Main, session: HTTPSession) =>
    _main = main'
    _session = session

  fun ref apply(response: Payload val) =>
    """
    Start receiving a response.  We get the status and headers.  Body data
    *might* be available.
    """
    _main.have_response(response)

  fun ref chunk(data: ByteSeq val) =>
    """
    Receive additional arbitrary-length response body data.
    """
    _main.have_body(data)

  fun ref finished() =>
    """
    This marks the end of the received body data.  We are done with the
    session.
    """
    _main.finished()
    _session.dispose()

  fun ref cancelled() =>
    _main.cancelled()