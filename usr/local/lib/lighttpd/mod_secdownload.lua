
-- extract tokens from url-path

local req_header = lighty.r.req_header

local secret = assert(req_header["X-secdl-secret"], "No X-secdl-secret!")
local docroot = assert(req_header["X-secdl-document-root"], "No X-secdl-document-root!")

local req_attr = lighty.r.req_attr

local uri_prefix = req_header["X-secdl-uri-prefix"] or "/sec"
local pattern = string.format("^%s/([%%w_-]+)(/(%%x+)(/.*))$", uri_prefix)

local mac, protected_path, ts, rel_path =
  string.match(req_attr["uri.path"], pattern)

if (not mac) then return 0 end
ts = tonumber(ts, 16)
if (not ts) then return 0 end

local path_segments = tonumber(req_header["X-secdl-path-segments"]) or 0
if (path_segments > 0) then
  pattern = "^(" .. string.rep("/[^/]+", path_segments + 1) .. ")"
  protected_path = string.match(protected_path, pattern)
  if (not protected_path) then return 0 end
end

local li = lighty.c

-- validate timestamp
local timeout = tonumber(req_header["X-secdl-timeout"]) or 3600
local t = li.time()
if (((t > ts) and (t - ts) or (ts - t)) > timeout) then
  return 410   -- 410 Gone; URI will never be valid again
end

-- validate MAC
local function hex2bin(str)
  return (str:gsub('..', function (cc)
    return string.char(tonumber(cc, 16))
  end))
end

local algorithm = req_header["X-secdl-algorithm"] or "sha256"
local hash = li.b64urlenc(hex2bin(li.hmac(algorithm, secret, protected_path)))
if (not li.secret_eq(hash, mac)) then
  return 403   -- 403 Forbidden
end

-- remap to alternative filesystem path
req_attr["physical.doc-root"] = docroot
req_attr["physical.basedir"] = docroot
req_attr["physical.path"] = docroot .. rel_path
req_attr["physical.rel-path"] = rel_path
-- let mod_staticfile or other module handle the file
