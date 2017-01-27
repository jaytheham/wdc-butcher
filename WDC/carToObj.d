module wdc.carToObj;

import std.stdio, std.file, wdc.car;

static class CarToObj
{
	static void convert(Car car, string destinationFolder)
	{
		import std.conv;
		
		if (!exists(destinationFolder) || !(destinationFolder.isDir))
		{
			mkdir(destinationFolder);
		}
		outputTextures(car, 2, destinationFolder);
		outputTextures(car, 1, destinationFolder);
		outputTextures(car, 0, destinationFolder);

		File output = File(destinationFolder ~ "car.obj", "w");
		int normalOffset = 1;
		int vertexOffest = 1;

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
		output.writeln("l ", vertexOffest, " ", vertexOffest + 1, " ", vertexOffest + 2,
		               " ", vertexOffest + 3, " ", vertexOffest);
		vertexOffest += 4;

		bool hasNormals;
		foreach (modelIndex, model; car.models)
		{
			foreach (vertex; model.vertices)
			{
				output.writeln("v ", vertex.x / 256.0, " ",
				                     vertex.y / 256.0, " ",
				                     vertex.z / 256.0);
			}
			
			foreach (normal; model.normals)
			{
				output.writeln("vn ", normal.x / 127.0, " ",
				                      normal.y / 127.0, " ",
				                      normal.z / 127.0);
			}

			foreach (sectionIndex, section; model.modelSections)
			{
				if (modelIndex == 0)
				{
					output.writeln("usemtl ", car.modelToTextureMap[sectionIndex]);
					output.writefln("o %.2d-%.2d-%s", modelIndex, sectionIndex, Car.partNames[sectionIndex]);
				}
				else
				{
					output.writeln("usemtl ", 14);
					output.writefln("o %.2d-%.2d", modelIndex, sectionIndex);
				}
				hasNormals = model.normals.length > 0;
				foreach (polygon; section.polygons)
				{
					foreach (uv; polygon.textureCoordinates)
					{
						output.writeln("vt ", uv.x / 80.0, " ", uv.y / 38.0);
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
					
				}
			}
			normalOffset += model.normals.length;
			vertexOffest += model.vertices.length;
		}
		output.close();
	}

	private static void outputTextures(Car car, int paletteSet, string destinationFolder)
	{
		import wdc.png;
		import std.string : format;
		enum byte TEXTURE_WIDTH = Car.TEXTURE_WIDTH_BYTES * 2;
		enum byte TEXTURE_HEIGHT = Car.TEXTURE_HEIGHT_BYTES;
		
		File materialLibrary = File(destinationFolder ~ "car.mtl", "w");
		Car.Colour[] palette;

		void writeTexture(ubyte[] textureBytes, int textureNum, int modelNum, int forceLitPalette)
		{
			uint paletteIndex = Car.MODEL_TO_PALETTE[modelNum] + forceLitPalette;
			string fileName = format("set%d_tex%.2d_pal%.2d.png", paletteSet, textureNum, paletteIndex);

			materialLibrary.writeln("newmtl ", textureNum);
			materialLibrary.writeln("illum 1");
			materialLibrary.writeln("map_Kd " ~ fileName);
			
			File textureFile = File(destinationFolder ~ fileName, "wb");
			palette = car.paletteSets[paletteSet][paletteIndex];
			textureFile.rawWrite(Png.wdcTextureToPng(palette, textureBytes, TEXTURE_WIDTH, TEXTURE_HEIGHT));
			textureFile.close();
		}

		foreach (textureIndex, texture; car.textures)
		{
			if (texture.length != Car.TEXTURE_SIZE_BYTES)
			{
				continue;
			}
			foreach (modelIndex, mapTextureIndex; car.modelToTextureMap)
			{
				if (mapTextureIndex == textureIndex)
				{
					// TODO: some cars have a third palette for the rear lights when reversing?
					writeTexture(texture, textureIndex, modelIndex, 0);
					if (modelIndex == 19 || modelIndex == 21)
					{
						writeTexture(texture, textureIndex, modelIndex, 1);
					}
				}
			}
		}
		materialLibrary.close();
	}
}