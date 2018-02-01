/*  Copyright (C) 2015, 2018  Vladimir Panteleev <vladimir@thecybershadow.net>
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Affero General Public License as
 *  published by the Free Software Foundation, either version 3 of the
 *  License, or (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

module dfeed.web.mailhide;

import std.base64;
import std.exception;
import std.uri;

import deimos.openssl.aes;
import deimos.openssl.evp;

import ae.net.ssl.openssl;
import ae.utils.sini;
import ae.utils.text;

class MailHide
{
	static struct Config
	{
		string publicKey, privateKey;
	}

private:
	immutable Config config;

	string pubKey;
	EVP_CIPHER_CTX e;

	void aesInit(ubyte[] key)
	{
		enforce(key.length == 16, "Invalid private key length");

		EVP_CIPHER_CTX_init(&e);
		EVP_EncryptInit_ex(&e, EVP_aes_128_cbc(), null, key.ptr, null).sslEnforce();
	}

	ubyte[] aesEncrypt(ubyte[] plaintext)
	{
		auto valLength = plaintext.length;
		auto padLength = ((plaintext.length + 15) / 16) * 16;
		plaintext.length = padLength;
		plaintext[valLength..padLength] = 16 - valLength % 16;
		
		int c_len = cast(uint)plaintext.length + AES_BLOCK_SIZE, f_len = 0;
		ubyte[] ciphertext = new ubyte[c_len];

		EVP_EncryptInit_ex(&e, null, null, null, null).sslEnforce();
		EVP_EncryptUpdate(&e, ciphertext.ptr, &c_len, plaintext.ptr, cast(uint)plaintext.length).sslEnforce();
		EVP_EncryptFinal_ex(&e, ciphertext.ptr+c_len, &f_len).sslEnforce();

		return ciphertext[0..c_len+f_len];
	}

	enum API_MAILHIDE_SERVER = "http://mailhide.recaptcha.net";

public:
	this(Config config)
	{
		this.config = config;
		aesInit(arrayFromHex(config.privateKey));
	}

	string getUrl(string email)
	{
		return API_MAILHIDE_SERVER ~ "/d" ~
			"?hl=en" ~
			"&k=" ~ encodeComponent(pubKey) ~ 
			"&c=" ~ cast(string)Base64URL.encode(aesEncrypt(cast(ubyte[])email))
		;
	}
}

MailHide mailHide;

static this()
{
	import dfeed.common : createService;
	mailHide = createService!MailHide("apis/mailhide");
}
