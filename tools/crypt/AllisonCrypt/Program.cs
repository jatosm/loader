// allison-crypt: AES-128-CBC envelope encrypter for Lua payloads.
// usage: allison-crypt <input.lua> [output.lua] [--fixed] [--self-test]
// Layers: AES-128-CBC (random key+IV per build) -> key split (k1 xor k2,
// recombined at runtime) -> base64 -> Lua stub with pure-Lua AES-128
// decryptor, length + PKCS7 integrity checks, junk decoys.
// The stub is plain Lua 5.1-subset: runs on Lua 5.1/5.4 AND Luau.
// Note: like every envelope, the key ships inside the stub, so this is
// strong deterrence, not immunity. Never put real secrets in the repo.
using System.Security.Cryptography;
using System.Text;

if (args.Contains("--self-test"))
{
	var rnd = new byte[64];
	RandomNumberGenerator.Fill(rnd);
	using var aes = Aes.Create();
	aes.KeySize = 128;
	aes.Mode = CipherMode.CBC;
	aes.Padding = PaddingMode.PKCS7;
	aes.GenerateKey();
	aes.GenerateIV();
	var ct = aes.CreateEncryptor().TransformFinalBlock(rnd, 0, rnd.Length);
	var pt = aes.CreateDecryptor().TransformFinalBlock(ct, 0, ct.Length);
	Console.WriteLine(rnd.SequenceEqual(pt) ? "self-test ok" : "SELF-TEST FAILED");
	return rnd.SequenceEqual(pt) ? 0 : 1;
}

var positional = args.Where(a => !a.StartsWith("--")).ToArray();
if (positional.Length < 1)
{
	Console.WriteLine("usage: allison-crypt <input.lua> [output.lua] [--fixed] [--self-test]");
	return 2;
}
var inPath = positional[0];
var outPath = positional.Length > 1 ? positional[1] : inPath + ".crypt.lua";
var fixedKeys = args.Contains("--fixed");

var source = await File.ReadAllTextAsync(inPath, Encoding.UTF8);
source = source.Replace("\r\n", "\n");
if (source.Length == 0)
{
	Console.Error.WriteLine("input is empty");
	return 3;
}
var plain = Encoding.UTF8.GetBytes(source);

byte[] key = new byte[16], iv = new byte[16];
if (fixedKeys)
{
	for (var i = 0; i < 16; i++) { key[i] = (byte)i; iv[i] = (byte)(16 + i); }
}
else
{
	RandomNumberGenerator.Fill(key);
	RandomNumberGenerator.Fill(iv);
}

byte[] cipher;
using (var aes = Aes.Create())
{
	aes.KeySize = 128;
	aes.Mode = CipherMode.CBC;
	aes.Padding = PaddingMode.PKCS7;
	aes.Key = key;
	aes.IV = iv;
	cipher = aes.CreateEncryptor().TransformFinalBlock(plain, 0, plain.Length);
}

var sysrand = new Random();
string SplitNum(int v)
{
	var r = sysrand.Next(1, 200);
	return $"({v + r}-{r})";
}
string ByteTable(byte[] b) => string.Join(",", b.Select(v => SplitNum(v)));

var k1 = new byte[16];
RandomNumberGenerator.Fill(k1);
var k2 = key.Select((v, i) => (byte)(v ^ k1[i])).ToArray();

var b64 = Convert.ToBase64String(cipher);
var chunks = Enumerable.Range(0, (b64.Length + 1023) / 1024)
	.Select(i => "'" + b64.Substring(i * 1024, Math.Min(1024, b64.Length - i * 1024)) + "'");

var pAlpha = new[] { "I", "l", "1" };
string Fresh(HashSet<string> taken)
{
	while (true)
	{
		var s = "___";
		for (var i = 0; i < 6; i++) s += pAlpha[sysrand.Next(3)];
		if (taken.Add(s)) return s;
	}
}
var taken = new HashSet<string>();
var P = args.Contains("--stable") ? "A" : Fresh(taken);

var stub = $$"""
local {{P}}k1={@@K1@@}
local {{P}}k2={@@K2@@}
local {{P}}v={@@IV@@}
local function {{P}}x(a,b) local r,m=0,1 for _=1,8 do local x,y=a%2,b%2 if x~=y then r=r+m end a=(a-x)/2 b=(b-y)/2 m=m*2 end return r end
local function {{P}}t(a) a=a*2 if a>=256 then a={{P}}x(a-256,27) end return a end
local function {{P}}m(a,b) local r=0 while b>0 do if b%2==1 then r={{P}}x(r,a) end a={{P}}t(a) b=math.floor(b/2) end return r end
local {{P}}pw=function(a,e) local r=1 while e>0 do if e%2==1 then r={{P}}m(r,a) end a={{P}}m(a,a) e=math.floor(e/2) end return r end
local function {{P}}rl(v,k) local p=1 for _=1,k do p=p*2 end return ((v*p)%256)+math.floor(v/(256/p)) end
local {{P}}s={} for {{P}}b=0,255 do local {{P}}v={{P}}b==0 and 0 or {{P}}pw({{P}}b,254) local {{P}}y={{P}}v for {{P}}k=1,4 do {{P}}y={{P}}x({{P}}y,{{P}}rl({{P}}v,{{P}}k)) end {{P}}s[{{P}}b+1]={{P}}x({{P}}y,99) end
local {{P}}u={} for {{P}}i=0,255 do {{P}}u[{{P}}s[{{P}}i+1]+1]={{P}}i end
local {{P}}r={1} for {{P}}i=2,10 do {{P}}r[{{P}}i]={{P}}t({{P}}r[{{P}}i-1]) end
local {{P}}k={} for {{P}}i=1,16 do {{P}}k[{{P}}i]={{P}}x({{P}}k1[{{P}}i],{{P}}k2[{{P}}i]) end
local {{P}}w={} for {{P}}i=0,15 do {{P}}w[{{P}}i+1]={{P}}k[{{P}}i+1] end
for {{P}}d=4,43 do local {{P}}a0,{{P}}a1,{{P}}a2,{{P}}a3={{P}}w[({{P}}d-1)*4+1],{{P}}w[({{P}}d-1)*4+2],{{P}}w[({{P}}d-1)*4+3],{{P}}w[({{P}}d-1)*4+4] if {{P}}d%4==0 then {{P}}a0,{{P}}a1,{{P}}a2,{{P}}a3={{P}}s[{{P}}a1+1],{{P}}s[{{P}}a2+1],{{P}}s[{{P}}a3+1],{{P}}s[{{P}}a0+1] {{P}}a0={{P}}x({{P}}a0,{{P}}r[{{P}}d/4]) end {{P}}w[{{P}}d*4+1]={{P}}x({{P}}w[({{P}}d-4)*4+1],{{P}}a0) {{P}}w[{{P}}d*4+2]={{P}}x({{P}}w[({{P}}d-4)*4+2],{{P}}a1) {{P}}w[{{P}}d*4+3]={{P}}x({{P}}w[({{P}}d-4)*4+3],{{P}}a2) {{P}}w[{{P}}d*4+4]={{P}}x({{P}}w[({{P}}d-4)*4+4],{{P}}a3) end
local function {{P}}f(b) local s={} for i=1,16 do s[i]={{P}}x(b[i],{{P}}w[160+i]) end for r=9,1,-1 do for w=0,3 do local t0,t1,t2,t3=s[w+1],s[w+5],s[w+9],s[w+13] local t={t0,t1,t2,t3} s[w+1],s[w+5],s[w+9],s[w+13]=t[(0-w)%4+1],t[(1-w)%4+1],t[(2-w)%4+1],t[(3-w)%4+1] end for i=1,16 do s[i]={{P}}u[s[i]+1] end local o=r*16 for i=1,16 do s[i]={{P}}x(s[i],{{P}}w[o+i]) end for c=0,3 do local a0,a1,a2,a3=s[c*4+1],s[c*4+2],s[c*4+3],s[c*4+4] s[c*4+1]={{P}}x({{P}}x({{P}}m(a0,14),{{P}}m(a1,11)),{{P}}x({{P}}m(a2,13),{{P}}m(a3,9))) s[c*4+2]={{P}}x({{P}}x({{P}}m(a0,9),{{P}}m(a1,14)),{{P}}x({{P}}m(a2,11),{{P}}m(a3,13))) s[c*4+3]={{P}}x({{P}}x({{P}}m(a0,13),{{P}}m(a1,9)),{{P}}x({{P}}m(a2,14),{{P}}m(a3,11))) s[c*4+4]={{P}}x({{P}}x({{P}}m(a0,11),{{P}}m(a1,13)),{{P}}x({{P}}m(a2,9),{{P}}m(a3,14))) end end for w=0,3 do local t0,t1,t2,t3=s[w+1],s[w+5],s[w+9],s[w+13] local t={t0,t1,t2,t3} s[w+1],s[w+5],s[w+9],s[w+13]=t[(0-w)%4+1],t[(1-w)%4+1],t[(2-w)%4+1],t[(3-w)%4+1] end for i=1,16 do s[i]={{P}}u[s[i]+1] end for i=1,16 do s[i]={{P}}x(s[i],{{P}}w[i]) end return s end
local {{P}}a='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local {{P}}b={} for {{P}}i=1,64 do {{P}}b[{{P}}a:sub({{P}}i,{{P}}i)]={{P}}i-1 end
local function {{P}}g(d) local o={} for i=1,#d,4 do local v0={{P}}b[d:sub(i,i)] or 0 local v1={{P}}b[d:sub(i+1,i+1)] or 0 local v2={{P}}b[d:sub(i+2,i+2)] or 0 local v3={{P}}b[d:sub(i+3,i+3)] or 0 o[#o+1]=string.char(v0*4+math.floor(v1/16)) if d:sub(i+2,i+2)~='=' then o[#o+1]=string.char((v1%16)*16+math.floor(v2/4)) end if d:sub(i+3,i+3)~='=' then o[#o+1]=string.char((v2%4)*64+v3) end end return table.concat(o) end
local {{P}}h={{P}}g(@@BLOB@@)
local {{P}}e={} local {{P}}q={} for {{P}}i=1,16 do {{P}}q[{{P}}i]={{P}}v[{{P}}i] end
for {{P}}j=0,(#{{P}}h/16)-1 do local {{P}}c={} for {{P}}i=1,16 do {{P}}c[{{P}}i]=string.byte({{P}}h,{{P}}j*16+{{P}}i) end local {{P}}y={{P}}f({{P}}c) for {{P}}i=1,16 do {{P}}e[#{{P}}e+1]=string.char({{P}}x({{P}}y[{{P}}i],{{P}}q[{{P}}i])) {{P}}q[{{P}}i]={{P}}c[{{P}}i] end end
local {{P}}p=table.concat({{P}}e)
if #{{P}}p~=@@LEN@@ then error('bad payload') end
local {{P}}n=string.byte({{P}}p,#{{P}}p)
if {{P}}n<1 or {{P}}n>16 then error('bad payload') end
for {{P}}i=0,{{P}}n-1 do if string.byte({{P}}p,#{{P}}p-{{P}}i)~={{P}}n then error('bad payload') end end
{{P}}p={{P}}p:sub(1,#{{P}}p-{{P}}n)
local {{P}}q=0 for {{P}}i=1,#{{P}}p do {{P}}q=({{P}}q+string.byte({{P}}p,{{P}}i))%4294967296 end
if {{P}}q~= @@SUM@@ then error('bad payload') end
if false then local {{P}}j1=(6*7) end
if false then local {{P}}j2=(9*11) end
assert((loadstring or load)({{P}}p))()
""";

var checksum = 0u;
foreach (var b in plain) checksum = (checksum + b) & 0xFFFFFFFFu;

stub = stub
	.Replace("@@K1@@", ByteTable(k1))
	.Replace("@@K2@@", ByteTable(k2))
	.Replace("@@IV@@", ByteTable(iv))
	.Replace("@@BLOB@@", string.Join("..", chunks))
	.Replace("@@LEN@@", SplitNum(cipher.Length))
	.Replace("@@SUM@@", SplitNum((int)checksum));

await File.WriteAllTextAsync(outPath, stub, Encoding.UTF8);
Console.WriteLine($"wrote {outPath} plain={plain.Length} cipher={cipher.Length}");
return 0;
