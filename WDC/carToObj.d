module wdc.carToObj;

import std.stdio, std.file, wdc.car, gfm.math;

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

		output.writeln("mtllib car.mtl");

		output.writeln("o ", Car.OBJ_WHEEL_ID);
		output.writeln("v ", car.wheelOrigins[0].x, " ", car.wheelOrigins[0].y, " ", car.wheelOrigins[0].z);
		output.writeln("v ", car.wheelOrigins[1].x, " ", car.wheelOrigins[1].y, " ", car.wheelOrigins[1].z);
		output.writeln("v ", car.wheelOrigins[2].x, " ", car.wheelOrigins[2].y, " ", car.wheelOrigins[2].z);
		output.writeln("v ", car.wheelOrigins[3].x, " ", car.wheelOrigins[3].y, " ", car.wheelOrigins[3].z);
		output.writeln("l 1 2 3 4 1");

		output.writeln("o ", Car.OBJ_LIGHT_ID);
		output.writeln("v ", car.lightOrigins[0].x, " ", car.lightOrigins[0].y, " ", car.lightOrigins[0].z);
		output.writeln("v ", car.lightOrigins[1].x, " ", car.lightOrigins[1].y, " ", car.lightOrigins[1].z);
		output.writeln("v ", car.lightOrigins[2].x, " ", car.lightOrigins[2].y, " ", car.lightOrigins[2].z);
		output.writeln("v ", car.lightOrigins[3].x, " ", car.lightOrigins[3].y, " ", car.lightOrigins[3].z);
		output.writeln("l 5 6 7 8 5");

		bool hasNormals;
		bool hasFourVerts = false;
		foreach (modelIndex, model; car.models)
		{
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
					foreach (polygonIndex; polygon.vertexIndices)
					{
						if (polygonIndex == 0xFFFF) // will always be the last index
						{
							hasFourVerts = false;
							continue;
						}
						vec3s vertex = model.vertices[polygonIndex];
						output.writeln("v ", vertex.x / 256.0, " ",
						                     vertex.y / 256.0, " ",
						                     vertex.z / 256.0);
						hasFourVerts = true;
					}
					if (hasNormals)
					{
						foreach (normalIndex; polygon.normalIndices)
						{
							vec3b normal = model.normals[normalIndex];
							output.writeln("vn ", normal.x / 127.0, " ",
							                      normal.y / 127.0, " ",
							                      normal.z / 127.0);
						}
					}
					foreach (uv; polygon.textureCoordinates)
					{
						output.writeln("vt ", uv.x / 80.0, " ", uv.y / 38.0);
					}
					output.write("f ", hasFourVerts ? "-4" : "-3",
						               "/-4/",
					                   hasNormals ? "-4" : "", " ",

					                   hasFourVerts ? "-3" : "-2",
					                   "/-3/",
					                   hasNormals ? "-3" : "", " ",

					                   hasFourVerts ? "-2" : "-1",
					                   "/-2/",
					                   hasNormals ? "-2" : "");
					if (hasFourVerts)
					{
						output.write(" -1/-1/", hasNormals ? "-1" : "");
					}
					output.writeln("");
				}
			}
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
			string fileName = modelNum > 29
			                  ? format("set%d_wheel_%d.png", paletteSet, modelNum - 30)
			                  : format("set%d_tex%.2d_pal%.2d.png", paletteSet, textureNum, paletteIndex);

			materialLibrary.writeln("newmtl ", textureNum);
			materialLibrary.writeln("illum 1");
			materialLibrary.writeln("map_Kd " ~ fileName);
			
			File textureFile = File(destinationFolder ~ fileName, "wb");
			palette = car.paletteSets[paletteSet][paletteIndex];
			textureFile.rawWrite(Png.wdcTextureToPng(palette, textureBytes, TEXTURE_WIDTH, TEXTURE_HEIGHT));
			textureFile.close();
		}

		int wheelNum = 0;
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
					writeTexture(texture, textureIndex, modelIndex > 29 ? 30 + wheelNum++ : modelIndex, 0);
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