module wdc.car;

import std.stdio,
	   std.array,
	   std.file,
	   std.bitmanip,
	   std.typecons,
	   camera,
	   gfm.math,
	   gfm.opengl,
	   wdc.tools,
	   wdc.drawable,
	   wdc.renderer,
	   wdc.carRenderer,
	   wdc.microcode;
// Car should accept either:
//  Binary files from the ROM
//  3D model files
// and convert them into an understandable, intermediate format from which it can output ROM compatible binaries
class Car : Drawable
{
	ubyte[] data;
	ubyte[] textures;
	ubyte[] palettes1;
	ubyte[] palettes2;
	ubyte[] palettes3;

	private
	{
		CarRenderer renderer;

		Header header;

		struct Header
		{
			float unknown1;
			float carCameraYOffset;
			vec3f[4] wheelOrigins;
			vec3f[4] headlightOrigins;
			TextureDescriptor[] bodyTextureDescriptors;
			TextureDescriptor[] wheelTextureDescriptors;
		}

		// There is one TextureDescriptor for each unique texture
		struct TextureDescriptor
		{
			G_SETTIMG setTImg;
			G_RDPLOADSYNC loadSync;
			G_LOADBLOCK loadBlock;
			G_ENDDL end;
		}
	}

	this(ubyte[] dataBlob, ubyte[] textureSource, ubyte[] palettesA, ubyte[] palettesB, ubyte[] palettesC)
	{
		data = dataBlob;
		textures = textureSource;
		palettes1 = palettesA;
		palettes2 = palettesB;
		palettes3 = palettesC;

		header = Header(data.readFloat(0x8),
		                data.readFloat(0xC),
		                [vec3f(data.readFloat(0x14),data.readFloat(0x18),data.readFloat(0x1C)),
		                vec3f(data.readFloat(0x20),data.readFloat(0x24),data.readFloat(0x28)),
		                vec3f(data.readFloat(0x2C),data.readFloat(0x30),data.readFloat(0x34)),
		                vec3f(data.readFloat(0x38),data.readFloat(0x3C),data.readFloat(0x40))],
		                [vec3f(data.readFloat(0x44),data.readFloat(0x48),data.readFloat(0x4C)),
		                vec3f(data.readFloat(0x50),data.readFloat(0x54),data.readFloat(0x58)),
		                vec3f(data.readFloat(0x5C),data.readFloat(0x60),data.readFloat(0x64)),
		                vec3f(data.readFloat(0x68),data.readFloat(0x6C),data.readFloat(0x70))]);

		int textureDescriptorPointers = data.readInt(0xB4);
		int textureDescriptorCount = data.readInt(0xB8);
		int descriptorLocation;

		foreach(index; 0..textureDescriptorCount)
		{
			descriptorLocation = data.readInt(textureDescriptorPointers + (index * 4));
			header.bodyTextureDescriptors ~= TextureDescriptor(G_SETTIMG(data.readULong(descriptorLocation)),
			                                                  G_RDPLOADSYNC(data.readULong(descriptorLocation + 8)),
			                                                  G_LOADBLOCK(data.readULong(descriptorLocation + 16)),
			                                                  G_ENDDL(data.readULong(descriptorLocation + 24)));
			
			assert(header.bodyTextureDescriptors[$ - 1].setTImg.id == 0xFD, "Unusual TextureDescriptor");
			assert(header.bodyTextureDescriptors[$ - 1].loadSync.id == 0xE6, "Unusual TextureDescriptor");
			assert(header.bodyTextureDescriptors[$ - 1].loadBlock.id == 0xF3, "Unusual TextureDescriptor");
			assert(header.bodyTextureDescriptors[$ - 1].end.id == 0xDF, "Unusual TextureDescriptor");
		}

		textureDescriptorPointers = data.readInt(0xDC);
		textureDescriptorCount = data.readInt(0xE0);

		foreach(index; 0..textureDescriptorCount)
		{
			descriptorLocation = data.readInt(textureDescriptorPointers + (index * 4));
			header.wheelTextureDescriptors ~= TextureDescriptor(G_SETTIMG(data.readULong(descriptorLocation)),
			                                                  G_RDPLOADSYNC(data.readULong(descriptorLocation + 8)),
			                                                  G_LOADBLOCK(data.readULong(descriptorLocation + 16)),
			                                                  G_ENDDL(data.readULong(descriptorLocation + 24)));
			
			assert(header.wheelTextureDescriptors[$ - 1].setTImg.id == 0xFD, "Unusual TextureDescriptor");
			assert(header.wheelTextureDescriptors[$ - 1].loadSync.id == 0xE6, "Unusual TextureDescriptor");
			assert(header.wheelTextureDescriptors[$ - 1].loadBlock.id == 0xF3, "Unusual TextureDescriptor");
			assert(header.wheelTextureDescriptors[$ - 1].end.id == 0xDF, "Unusual TextureDescriptor");
		}
	}

	void setupDrawing(OpenGL opengl)
	{
		renderer = new CarRenderer(this, opengl);
	}

	void draw(Camera camera, char[] keys)
	{
		renderer.draw(camera, keys);
	}
}
