module wdc.carToObj;

import std.stdio, std.file, wdc.car;

static class CarToObj
{
	static void convert(Car car)
	{
		import std.conv;
		
		if (!exists("output") || !("output".isDir))
		{
			mkdir("output");
		}
		outputTextures(car);
		outputTextures(car, 1);
		outputTextures(car, 2);
		File output = File("output/car.obj", "w");
		int normalOffset = 1;
		int vertexOffest = 1;
		int uvOffset = 1;
		output.writeln("mtllib car.mtl");
		output.writeln("o ", Car.OBJ_WHEEL_ID);
		output.writeln("v ", car.wheelOrigins[0].x, " ", car.wheelOrigins[0].y, " ", car.wheelOrigins[0].z);
		output.writeln("v ", car.wheelOrigins[1].x, " ", car.wheelOrigins[1].y, " ", car.wheelOrigins[1].z);
		output.writeln("v ", car.wheelOrigins[2].x, " ", car.wheelOrigins[2].y, " ", car.wheelOrigins[2].z);
		output.writeln("v ", car.wheelOrigins[3].x, " ", car.wheelOrigins[3].y, " ", car.wheelOrigins[3].z);
		output.writeln("l 1 2 3 4 1");
		vertexOffest += 4;

		output.writeln("o ", Car.OBJ_LIGHT_ID);
		output.writeln("v ", car.lightOrigins[0].x, " ", car.lightOrigins[0].y, " ", car.lightOrigins[0].z);
		output.writeln("v ", car.lightOrigins[1].x, " ", car.lightOrigins[1].y, " ", car.lightOrigins[1].z);
		output.writeln("v ", car.lightOrigins[2].x, " ", car.lightOrigins[2].y, " ", car.lightOrigins[2].z);
		output.writeln("v ", car.lightOrigins[3].x, " ", car.lightOrigins[3].y, " ", car.lightOrigins[3].z);
		output.writeln("l ", vertexOffest, " ", vertexOffest + 1, " ", vertexOffest + 2, " ", vertexOffest + 3, " ", vertexOffest);
		vertexOffest += 4;

		bool hasNormals;
		foreach (mIndex, currentModel; car.models)
		{
			foreach (vertex; currentModel.vertices)
			{
				output.writeln("v ", vertex.x / 256.0, " ",
				                     vertex.y / 256.0, " ",
				                     vertex.z / 256.0);
			}
			
			foreach (normal; currentModel.normals)
			{
				output.writeln("vn ", normal.x / 127.0, " ",
				                      normal.y / 127.0, " ",
				                      normal.z / 127.0);
			}

			foreach (sIndex, ms; currentModel.modelSections)
			{
				if (mIndex == 0)
				{
					output.writeln("usemtl ", car.modelToTextureMap[sIndex]);
					output.writefln("o %.2d-%.2d-%s", mIndex, sIndex, Car.partNames[sIndex]);
				}
				else
				{
					output.writeln("usemtl ", 14);
					output.writefln("o %.2d-%.2d", mIndex, sIndex);
				}
				hasNormals = currentModel.normals.length > 0;
				foreach (polygon; ms.polygons)
				{
					foreach (uvi, uv; polygon.textureCoordinates)
					{
						output.writeln("vt ", uv.u / 80.0, " ", uv.v / 38.0);
					}
					output.write("f ", polygon.vertexIndices[0] + vertexOffest, "/-4/",
					                     hasNormals ? to!string(polygon.normalIndices[0] + normalOffset) : "", " ",

					                     polygon.vertexIndices[1] + vertexOffest, "/-3/",
					                     hasNormals ? to!string(polygon.normalIndices[1] + normalOffset) : "", " ",

					                     polygon.vertexIndices[2] + vertexOffest, "/-2/",
					                     hasNormals ? to!string(polygon.normalIndices[2] + normalOffset) : "");
					if (polygon.vertexIndices[3] != 0xFFFF)
					{
						output.write(" ", polygon.vertexIndices[3] + vertexOffest, "/-1/",
						             hasNormals ? to!string(polygon.normalIndices[3] + normalOffset) : "");
					}
					output.writeln("");
					uvOffset += 4;
				}
			}
			normalOffset += currentModel.normals.length;
			vertexOffest += currentModel.vertices.length;
		}
	}

	private static void outputTextures(Car car, int paletteSet = 0)
	{
		import wdc.png;
		import std.string : format;
		enum byte TEXTURE_WIDTH = 80, TEXTURE_HEIGHT = 38;
		enum int TEXTURE_SIZE_BYTES = (TEXTURE_WIDTH * TEXTURE_HEIGHT) / 2;
		
		File materialLibraryFile = File("output/car.mtl", "w");
		Car.Colour[] curPalette;
		int texNum, modelNum;

		void writeTexture(ubyte[] textureBytes, int alternate)
		{
			materialLibraryFile.writeln("newmtl ", texNum);
			materialLibraryFile.writeln("illum 0");
			materialLibraryFile.writeln(format("map_Kd -clamp on .\\%d_car%.2d_%d.png", 0, texNum, alternate));
			
			File textureFile = File(format("output/%d_car%.2d_%d.png", paletteSet, texNum, alternate), "wb");
			curPalette = car.palettes[paletteSet][Car.MODEL_TO_PALETTE[modelNum + alternate]];
			textureFile.rawWrite(Png.wdcTextureToPng(curPalette, textureBytes, TEXTURE_WIDTH, TEXTURE_HEIGHT));
			textureFile.close();
		}

		foreach (texIndex, texture; car.textures)
		{
			foreach (modelIndex, textureIndex; car.modelToTextureMap)
			{
				if (textureIndex == texIndex)
				{
					texNum = textureIndex;
					modelNum = modelIndex;
					break;
				}
			}
			
			if (texture.length != TEXTURE_SIZE_BYTES)
			{
				continue;
			}
			writeTexture(texture, 0);
			// For the second of each light, we're outputting the lit version of the texture
			// TODO: pretty sure there is a third palette for the rear lights when reversing
			if (modelNum == 19 || modelNum == 21)
			{
				writeTexture(texture, 1);
			}
		}
		materialLibraryFile.close();
	}
}