module wdc.car;

import std.stdio,
	   std.array,
	   std.file,
	   std.bitmanip,
	   std.typecons;

import camera;

import gfm.math,
	   gfm.opengl;

class Car
{
	private
	{
		struct Vertex
		{
			vec3i position;
			vec2f vertexUV;
		}

		ubyte[] dataBlob;
		Vertex[] carVertices;
		mat4f model;
		GLProgram program;
		OpenGL openGL;
		GLVAO vao;
		GLBuffer vbo;
		VertexSpecification!Vertex vs;

		int modelBlockIndex = 0;
		int numModelBlocks = 0;

		enum modelBlockPointerOffset = 0xf4;
		enum textureCMDPointersOffset = 0xa0;
		enum textureBlobOffset = 0x538;

		int textureWidth = 80;
		int textureHeight = 38;
		GLTexture2D texture;
		ubyte[] textureBytes;
	}

	this(ubyte[] data, ubyte[] textures)
	{
		createFromBinary(data, textures);
	}

	void enableDrawing(OpenGL opengl, GLProgram prgrm)
	{
		openGL = opengl;
		program = prgrm;
		model = mat4f.identity();

		vs = new VertexSpecification!Vertex(program);

		setupBuffers();
	}

	void draw(Camera cam)
	{
		texture.use(0);
		program.uniform("myTextureSampler").set(0);
		program.uniform("mvpMatrix").set(cam.getPVM(model));
		program.use();
		vao.bind();
		glDrawArrays(GL_TRIANGLES, 0, carVertices.length);
		vao.unbind();
		program.unuse();
	}

	void nextModelBlock()
	{
		setModelBlock(modelBlockIndex + 1);
	}

	void prevModelBlock()
	{
		setModelBlock(modelBlockIndex - 1);
	}

	void setModelBlock(int blockNum)
	{
		modelBlockIndex = blockNum;
		if (modelBlockIndex < 0)
		{
			modelBlockIndex = numModelBlocks - 1;
		}
		else if (modelBlockIndex >= numModelBlocks)
		{
			modelBlockIndex = 0;
		}
		loadModelData();
		updateBuffers();
	}

private:
	void createFromBinary(ubyte[] data, ubyte[] textures)
	{
		// Here we clip the texture data because uncompress seems to be giving enlarged output sometimes
		dataBlob = replaceSlice(data, data[0x538..0x93b8], textures[0..0x8e80]);
		std.file.write("datablob", dataBlob);

		while (peek!int(dataBlob[modelBlockPointerOffset + numModelBlocks * 0x10
		                         ..
		                         modelBlockPointerOffset + 4 + numModelBlocks * 0x10]) > 0)
		{
			numModelBlocks++;
		}
		
		loadModelData();
	}

	void updateBuffers()
	{
		vbo.setData(carVertices[]);
	}

	void setupBuffers()
	{
		vao = new GLVAO(openGL);
		vao.bind();
		vbo = new GLBuffer(openGL, GL_ARRAY_BUFFER, GL_STATIC_DRAW, carVertices[]);
		vs.use();
		vao.unbind();
		setupTextures();
	}

	void loadModelData()
	{
		loadVertices();
		loadTexture();

		if (carVertices.length < 3)
		{
			writeln("NOTE: Too few vertices defined to draw anything");
		}
	}

	void loadTexture()
	{
		textureBytes.length = 0;
		// use modelBlockIndex to index into the first lot of texture pointer pointers
		int textureCmdPointers = peek!int(dataBlob[textureCMDPointersOffset..textureCMDPointersOffset + 4]);
		writefln("a %x", textureCmdPointers);
		int textureCmdPointer = textureCmdPointers + modelBlockIndex * 4;
		writefln("b %x", textureCmdPointer);
		int textureCmdOffset = peek!int(dataBlob[textureCmdPointer..textureCmdPointer + 4]);
		writefln("c %x", textureCmdOffset);

		// get the texture offset from the command
		int textureOffset = peek!int(dataBlob[textureCmdOffset + 4..textureCmdOffset + 8]);
		writefln("d %x", textureOffset);

		/// grab the palette, convert to 1 byte per color component
		/// create the final array from the palette
		int maxWidth = textureWidth / 2;
		int maxHeight = textureHeight;
		int w = 0, h = 0;
		while (h < maxHeight)
		{
			w = 0;
			while (w < maxWidth)
			{
				//writeln("L1");
				textureBytes ~= dataBlob[textureOffset + w + (h * maxWidth)] & 0xf0;
				//writefln("%x", textureOffset + w + (h * maxWidth));
				textureBytes ~= (dataBlob[textureOffset + w + (h * maxWidth)] & 0x0f) << 4;
				//writefln("::%x %x", textureBytes[$ -1], textureBytes[$ -2]);
				//readln();
				w++;
			}
			if (h % 2 == 1)
				{
					
					byte tempByte = textureBytes[$ - textureWidth];
					textureBytes[$ - textureWidth] = textureBytes[($ - textureWidth) + 8];
					textureBytes[($ - textureWidth) + 8] = tempByte;

					tempByte = textureBytes[($ - textureWidth) + 1];
					textureBytes[($ - textureWidth) + 1] = textureBytes[($ - textureWidth) + 9];
					textureBytes[($ - textureWidth) + 9] = tempByte;

					tempByte = textureBytes[($ - textureWidth) + 2];
					textureBytes[($ - textureWidth) + 2] = textureBytes[($ - textureWidth) + 10];
					textureBytes[($ - textureWidth) + 10] = tempByte;

					tempByte = textureBytes[($ - textureWidth) + 3];
					textureBytes[($ - textureWidth) + 3] = textureBytes[($ - textureWidth) + 11];
					textureBytes[($ - textureWidth) + 11] = tempByte;

					tempByte = textureBytes[($ - textureWidth) + 4];
					textureBytes[($ - textureWidth) + 4] = textureBytes[($ - textureWidth) + 12];
					textureBytes[($ - textureWidth) + 12] = tempByte;

					tempByte = textureBytes[($ - textureWidth) + 5];
					textureBytes[($ - textureWidth) + 5] = textureBytes[($ - textureWidth) + 13];
					textureBytes[($ - textureWidth) + 13] = tempByte;

					tempByte = textureBytes[($ - textureWidth) + 6];
					textureBytes[($ - textureWidth) + 6] = textureBytes[($ - textureWidth) + 14];
					textureBytes[($ - textureWidth) + 14] = tempByte;

					tempByte = textureBytes[($ - textureWidth) + 7];
					textureBytes[($ - textureWidth) + 7] = textureBytes[($ - textureWidth) + 15];
					textureBytes[($ - textureWidth) + 15] = tempByte;

					//writeln(textureBytes);
					//writefln("__ %x %x %x %x", textureBytes[$-4], textureBytes[$-3],textureBytes[$-2],textureBytes[$-1]);

					// row end
					tempByte = textureBytes[$ - 8];
					textureBytes[$ - 8] = textureBytes[$ - 16];
					textureBytes[$ - 16] = tempByte;

					tempByte = textureBytes[$ - 7];
					textureBytes[$ - 7] = textureBytes[$ - 15];
					textureBytes[$ - 15] = tempByte;

					tempByte = textureBytes[$ - 6];
					textureBytes[$ - 6] = textureBytes[$ - 14];
					textureBytes[$ - 14] = tempByte;

					tempByte = textureBytes[$ - 5];
					textureBytes[$ - 5] = textureBytes[$ - 13];
					textureBytes[$ - 13] = tempByte;

					tempByte = textureBytes[$ - 4];
					textureBytes[$ - 4] = textureBytes[$ - 12];
					textureBytes[$ - 12] = tempByte;

					tempByte = textureBytes[$ - 3];
					textureBytes[$ - 3] = textureBytes[$ - 11];
					textureBytes[$ - 11] = tempByte;

					tempByte = textureBytes[$ - 2];
					textureBytes[$ - 2] = textureBytes[$ - 10];
					textureBytes[$ - 10] = tempByte;

					tempByte = textureBytes[$ - 1];
					textureBytes[$ - 1] = textureBytes[$ - 9];
					textureBytes[$ - 9] = tempByte;

					//writefln("__ %x %x %x %x", textureBytes[$-4], textureBytes[$-3],textureBytes[$-2],textureBytes[$-1]);
					//readln();
				}
			h++;
		}
		std.file.write("out_texture.raw", textureBytes);
	}

	void setupTextures()
	{
		texture = new GLTexture2D(openGL);
		texture.setMinFilter(GL_NEAREST);
		texture.setMagFilter(GL_NEAREST);
		texture.setImage(0, GL_R3_G3_B2, 80, 38, 0, GL_RGB, GL_UNSIGNED_BYTE_3_3_2, textureBytes.ptr);
	}

	Vertex getVertex(int vertexOffset, int polygonOffset, int vertNum)
	{
		return Vertex(vec3i(peek!short(dataBlob[vertexOffset    ..vertexOffset + 2]),
							peek!short(dataBlob[vertexOffset + 4..vertexOffset + 6]),
							peek!short(dataBlob[vertexOffset + 2..vertexOffset + 4])),
						vec2f(cast(byte)dataBlob[polygonOffset + 0x10 + vertNum * 2] / cast(float)textureWidth,
							  cast(byte)dataBlob[polygonOffset + 0x11 + vertNum * 2] / cast(float)textureHeight));
	}

	void loadVertices()
	{
		int pointerOffset = modelBlockPointerOffset + modelBlockIndex * 0x10;
		int modelBlockOffset = peek!int(dataBlob[pointerOffset..pointerOffset + 4]);
		int verticesOffset = peek!int(dataBlob[modelBlockOffset + 0 .. modelBlockOffset + 4]);
		//int vertexCount = peek!int(dataBlob[modelBlockOffset + 4 .. modelBlockOffset + 8]);
		int polygonOffset = peek!int(dataBlob[modelBlockOffset + 8 .. modelBlockOffset + 12]);
		int polygonCount = peek!int(dataBlob[modelBlockOffset + 12 .. modelBlockOffset + 16]);
		
		carVertices.length = 0;
		ushort v1, v2, v3, v4;
		int curVertOffset;

		while (polygonCount > 0)
		{
			v1 = peek!ushort(dataBlob[polygonOffset + 8 .. polygonOffset + 10]);
			v2 = peek!ushort(dataBlob[polygonOffset + 10 .. polygonOffset + 12]);
			v3 = peek!ushort(dataBlob[polygonOffset + 12 .. polygonOffset + 14]);
			v4 = peek!ushort(dataBlob[polygonOffset + 14 .. polygonOffset + 16]);

			if (v4 == 0xffff) // One triangle
			{
				curVertOffset = verticesOffset + v1 * 6;
				carVertices ~= getVertex(curVertOffset, polygonOffset, 0);
				curVertOffset = verticesOffset + v2 * 6;
				carVertices ~= getVertex(curVertOffset, polygonOffset, 1);
				curVertOffset = verticesOffset + v3 * 6;
				carVertices ~= getVertex(curVertOffset, polygonOffset, 2);
			}
			else // Two Triangles
			{
				curVertOffset = verticesOffset + v1 * 6;
				carVertices ~= getVertex(curVertOffset, polygonOffset, 0);
				curVertOffset = verticesOffset + v2 * 6;
				carVertices ~= getVertex(curVertOffset, polygonOffset, 1);
				curVertOffset = verticesOffset + v3 * 6;
				carVertices ~= getVertex(curVertOffset, polygonOffset, 2);

				curVertOffset = verticesOffset + v1 * 6;
				carVertices ~= getVertex(curVertOffset, polygonOffset, 0);
				curVertOffset = verticesOffset + v3 * 6;
				carVertices ~= getVertex(curVertOffset, polygonOffset, 2);
				curVertOffset = verticesOffset + v4 * 6;
				carVertices ~= getVertex(curVertOffset, polygonOffset, 3);
			}

			polygonOffset += 0x20;
			polygonCount--;
		}
	}

	void createFromModel(ubyte[] data)
	{
		writeln("**** UNIMPLEMENTED ****");
	}
}