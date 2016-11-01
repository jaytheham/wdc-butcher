module wdc.carFromObj;

import wdc.car, wdc.png,
	
	   gfm.math,

	   std.algorithm, std.stdio, std.string, std.conv;

static class CarFromObj
{
	public static Car convert(string objFilePath)
	{
		Car car = new Car();
		int currentModel = 0xffff, currentModelSection,
		    totalVertexCount = 0, sectionVertexCount = 0,
		    normalOffset, sectionNormalCount,
		    uvOffset;
		string line;
		string[] lineParts, materialPaths;
		Car.TextureCoordinate[] sectionUvs;
		string[][] faces;
		File input = File(objFilePath, "r");

		void facesToPolygons()
		{
			ushort convertVertexPointer(string[] point)
			{
				return cast(ushort)((parse!uint(point[0]) - totalVertexCount - 1) +
					(car.models[currentModel].vertices.length - sectionVertexCount));
			}
			ushort convertNormalPointer(string[] point)
			{
				return cast(ushort)((parse!uint(point[2]) - normalOffset - 1) +
					(car.models[currentModel].normals.length - sectionNormalCount));
			}
			string[] point1, point2, point3, point4;
			foreach (face; faces)
			{
				point1 = split(face[0], "/");
				point2 = split(face[1], "/");
				point3 = split(face[2], "/");
				point4 = face.length == 4 ? split(face[3], "/") : null;
				car.models[currentModel].modelSections[currentModelSection].polygons ~= Car.Polygon(
					[
					convertVertexPointer(point1),
					convertVertexPointer(point2),
					convertVertexPointer(point3),
					point4 != null ? convertVertexPointer(point4) : cast(ushort)0xFFFF
					],
					[
					sectionUvs[parse!uint(point1[1]) - uvOffset - 1],
					sectionUvs[parse!uint(point2[1]) - uvOffset - 1],
					sectionUvs[parse!uint(point3[1]) - uvOffset - 1],
					point4 != null ? sectionUvs[parse!uint(point4[1]) - uvOffset - 1] : Car.TextureCoordinate(0,0)
					],
					[
					convertNormalPointer(point1),
					convertNormalPointer(point2),
					convertNormalPointer(point3),
					point4 != null ? convertNormalPointer(point4) : 0
					]
					);
			}
		}

		while((line = input.readln()) !is null)
		{
			line = chomp(line);
			
			if (line.startsWith("o "))
			{
				if (currentModel != 0xffff)
				{
					facesToPolygons();
				}
				lineParts = split(line[2..$], "-");
				if (lineParts[0] == Car.OBJ_WHEEL_ID)
				{
					foreach (i; 0..4)
					{
						line = input.readln();
						assert(line.startsWith("v "), "Less than four wheel origin vertices");
						lineParts = split(line[2..$], " ");
						car.wheelOrigins[i] = vec3f(parse!float(lineParts[0]),
						                        parse!float(lineParts[1]),
						                        parse!float(lineParts[2]));
					}
					totalVertexCount += 4;
					currentModel = 0xffff;
				}
				else if (lineParts[0] == Car.OBJ_LIGHT_ID)
				{
					foreach (i; 0..4)
					{
						line = input.readln();
						assert(line.startsWith("v "), "Less than four light origin vertices");
						lineParts = split(line[2..$], " ");
						car.lightOrigins[i] = vec3f(parse!float(lineParts[0]),
						                        parse!float(lineParts[1]),
						                        parse!float(lineParts[2]));
					}
					totalVertexCount += 4;
					currentModel = 0xffff;
				}
				else if (lineParts.length >= 2)
				{
					// new section
					currentModel = parse!int(lineParts[0]);
					currentModelSection = parse!int(lineParts[1]);
					while (car.models[currentModel].modelSections.length <= currentModelSection)
					{
						car.models[currentModel].modelSections ~= Car.ModelSection();
					}
					totalVertexCount += sectionVertexCount;
					normalOffset += sectionNormalCount;
					uvOffset += sectionUvs.length;
					sectionNormalCount = 0;
					sectionVertexCount = 0;
					sectionUvs.length = 0;
					faces.length = 0;
				}
			}
			else if (line.startsWith("v "))
			{
				lineParts = split(line[2..$], " ");
				car.models[currentModel].vertices ~= Car.Vertex(
					                                    cast(short)(parse!float(lineParts[2]) * 256),
					                                    cast(short)(parse!float(lineParts[0]) * 256),
					                                    cast(short)(parse!float(lineParts[1]) * 256)
					                                   );
				sectionVertexCount++;
			}
			else if (line.startsWith("vn "))
			{
				lineParts = split(line[3..$], " ");
				car.models[currentModel].normals ~= Car.Normal(
					                                   cast(byte)(parse!float(lineParts[2]) * 127),
					                                   cast(byte)(parse!float(lineParts[0]) * 127),
					                                   cast(byte)(parse!float(lineParts[1]) * 127)
					                                  );
				sectionNormalCount++;
			}
			else if (line.startsWith("vt "))
			{
				lineParts = split(line[3..$], " ");
				sectionUvs ~= Car.TextureCoordinate(
					                            cast(byte)(parse!float(lineParts[0]) * 80),
					                            cast(byte)(parse!float(lineParts[1]) * 38)
					                           );
			}
			else if (line.startsWith("f "))
			{
				lineParts = split(line[2..$], " ");
				faces ~= lineParts;
			}
			else if (line.startsWith("mtllib "))
			{
				lineParts = split(line, " ");
				if (canFind(lineParts[1], '\\') || canFind(lineParts[1], '/'))
				{
					materialPaths = texturePathsFromMtl(lineParts[1]);
				}
				else
				{
					int folderEndIndex = lastIndexOf(objFilePath, '/') != -1 ? lastIndexOf(objFilePath, '/') : lastIndexOf(objFilePath, '\\');
					string materialLibraryPath = objFilePath[0..folderEndIndex + 1] ~ lineParts[1];
					materialPaths = texturePathsFromMtl(materialLibraryPath);
				}
				foreach (path; materialPaths)
				{
					if (path != "")
					{
						car.textures ~= Png.pngToWdcTexture(path);
					}
					else
					{
						car.textures ~= new ubyte[8];
					}
				}
			}
			else if (line.startsWith("usemtl "))
			{
				lineParts = split(line, " ");
				int materialIndex = parse!int(lineParts[1]);
				if (currentModel == 0)
				{
					car.modelToTextureMap[currentModelSection] = materialIndex;
					car.palettes[0][Car.MODEL_TO_PALETTE[currentModelSection]] = Png.pngToWdcPalette(materialPaths[materialIndex]);
				}
			}
		}
		facesToPolygons();
		
		car.textures ~= Png.pngToWdcTexture("output\\0_car22_0.png");
		car.textures ~= Png.pngToWdcTexture("output\\0_car23_0.png");
		car.textures ~= Png.pngToWdcTexture("output\\0_car24_0.png");
		car.textures ~= Png.pngToWdcTexture("output\\0_car25_0.png");
		car.modelToTextureMap[0x1E] = 22;
		car.modelToTextureMap[0x1F] = 23;
		car.modelToTextureMap[0x20] = 24;
		car.modelToTextureMap[0x21] = 25;

		car.insertedPaletteIndices = [0,1,2,3,4,5,6,7];
		input.close();
		//removeRepeatedVertices();
		//generateBinaries();
		return car;
	}

	private static string[] texturePathsFromMtl(string mtlLibraryPath)
	{
		import std.conv, std.string;

		string[] texturePaths = new string[0x16], lineParts;
		int textureNum;
		string line;
		File input = File(mtlLibraryPath, "r");
		while((line = input.readln()) !is null)
		{
			if (line.startsWith("newmtl "))
			{
				lineParts = split(line, " ");
				textureNum = parse!int(lineParts[1]);
			}
			if (line.startsWith("map_Kd "))
			{
				lineParts = split(line, "map_Kd ");
				texturePaths[textureNum] = chomp(lineParts[1]);
			}
		}
		input.close();
		return texturePaths;
	}


}