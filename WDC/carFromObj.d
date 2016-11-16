module wdc.carFromObj;

import wdc.car, wdc.png, wdc.tools,
	
	   gfm.math,

	   std.algorithm, std.stdio, std.string, std.conv;

static class CarFromObj
{
	public static Car convert(string objFilePath)
	{
		int model = 0xFFFF, modelSection,
		    totalVertexCount = 0, sectionVertexCount = 0,
		    totalNormalCount = 0, sectionNormalCount = 0,
		    totalUvCount = 0;
		string line;
		string[][] faces;
		string[] lineParts, materialPaths;
		Car.TextureCoordinate[] sectionUvs;
		
		Car car = new Car();
		File input = File(objFilePath, "r");

		void facesToPolygons(bool reusePrevious)
		{
			ushort convertVertexPointer(uint vertexIndex)
			{
				return cast(ushort)((vertexIndex - totalVertexCount - 1) +
					(car.models[model].vertices.length - sectionVertexCount));
			}
			ushort convertNormalPointer(uint normalIndex)
			{
				return cast(ushort)((normalIndex - totalNormalCount - 1) +
					(car.models[model].normals.length - sectionNormalCount));
			}
			float distanceBetween(Car.Vertex a, Car.Vertex b)
			{
				import std.math;
				return sqrt(cast(float)(pow((b.x - a.x), 2) + pow((b.y - a.y), 2) + pow((b.z - a.z), 2)));
			}
			ushort findNearestPoint(ushort toIndex)
			{
				import std.math : abs;
				uint closestIndex;
				float distance = 100_000.0;
				float temp;
				foreach (fromIndex, vertex; car.models[model].vertices[0..$-sectionVertexCount])
				{
					temp = distanceBetween(car.models[model].vertices[fromIndex], car.models[model].vertices[toIndex]);
					if (abs(temp) < distance)
					{
						distance = temp;
						closestIndex = fromIndex;
					}
				}
				return cast(ushort)closestIndex;
			}
			string[] point1, point2, point3, point4;
			foreach (face; faces)
			{
				point1 = split(face[0], "/");
				point2 = split(face[1], "/");
				point3 = split(face[2], "/");
				point4 = face.length == 4 ? split(face[3], "/") : null;
				car.models[model].modelSections[modelSection].polygons ~= Car.Polygon(
					[
					reusePrevious ? findNearestPoint(convertVertexPointer(parse!uint(point1[0]))) : convertVertexPointer(parse!uint(point1[0])),
					reusePrevious ? findNearestPoint(convertVertexPointer(parse!uint(point2[0]))) : convertVertexPointer(parse!uint(point2[0])),
					reusePrevious ? findNearestPoint(convertVertexPointer(parse!uint(point3[0]))) : convertVertexPointer(parse!uint(point3[0])),
					point4 != null ? (reusePrevious ? findNearestPoint(convertVertexPointer(parse!uint(point4[0]))) : convertVertexPointer(parse!uint(point4[0]))) : cast(ushort)0xFFFF
					],
					[
					sectionUvs[parse!uint(point1[1]) - totalUvCount - 1],
					sectionUvs[parse!uint(point2[1]) - totalUvCount - 1],
					sectionUvs[parse!uint(point3[1]) - totalUvCount - 1],
					point4 != null ? sectionUvs[parse!uint(point4[1]) - totalUvCount - 1] : Car.TextureCoordinate(0,0)
					],
					[
					convertNormalPointer(parse!uint(point1[2])),
					convertNormalPointer(parse!uint(point2[2])),
					convertNormalPointer(parse!uint(point3[2])),
					point4 != null ? convertNormalPointer(parse!uint(point4[2])) : 0
					]
					);
			}
		}

		while((line = input.readln()) !is null)
		{
			line = chomp(line);
			
			if (line.startsWith("o "))
			{
				if (model != 0xFFFF)
				{
					facesToPolygons(modelSection == 26 || modelSection == 27 || modelSection == 28);
					if (modelSection == 26 || modelSection == 27 || modelSection == 28)
					{
						car.models[model].vertices.length -= sectionVertexCount;
					}
				}
				lineParts = split(line[2..$], "-");
				if (lineParts.length >= 2)
				{
					// new section
					model = parse!int(lineParts[0]);
					modelSection = parse!int(lineParts[1]);
					while (car.models[model].modelSections.length <= modelSection)
					{
						car.models[model].modelSections ~= Car.ModelSection();
					}
					totalVertexCount += sectionVertexCount;
					totalNormalCount += sectionNormalCount;
					totalUvCount += sectionUvs.length;
					sectionNormalCount = 0;
					sectionVertexCount = 0;
					sectionUvs.length = 0;
					faces.length = 0;
				}
				else if (lineParts[0] == Car.OBJ_WHEEL_ID)
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
					model = 0xFFFF;
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
					model = 0xFFFF;
				}
			}
			else if (line.startsWith("v "))
			{
				lineParts = split(line[2..$], " ");
				car.models[model].vertices ~= Car.Vertex(cast(short)(parse!float(lineParts[2]) * 256),
				                                         cast(short)(parse!float(lineParts[0]) * 256),
				                                         cast(short)(parse!float(lineParts[1]) * 256));
				sectionVertexCount++;
			}
			else if (line.startsWith("vn "))
			{
				lineParts = split(line[3..$], " ");
				car.models[model].normals ~= Car.Normal(cast(byte)(parse!float(lineParts[2]) * 127),
				                                        cast(byte)(parse!float(lineParts[0]) * 127),
				                                        cast(byte)(parse!float(lineParts[1]) * 127));
				sectionNormalCount++;
			}
			else if (line.startsWith("vt "))
			{
				lineParts = split(line[3..$], " ");
				sectionUvs ~= Car.TextureCoordinate(cast(byte)(parse!float(lineParts[0]) * 80),
				                                    cast(byte)(parse!float(lineParts[1]) * 38));
			}
			else if (line.startsWith("f "))
			{
				lineParts = split(line[2..$], " ");
				faces ~= lineParts;
			}
			else if (line.startsWith("mtllib "))
			{
				lineParts = split(line, " ");
				if (canFind(lineParts[1], '\\') || canFind(lineParts[1], '/')) // Absolute path, hopefully
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
						// it seems all 'missing' textures can be 8
						// but only some can be 0, how to tell?
						car.textures ~= new ubyte[8];
					}
				}
			}
			else if (line.startsWith("usemtl ") && model == 0)
			{
				lineParts = split(line, " ");
				int materialIndex = parse!int(lineParts[1]);
				car.modelToTextureMap[modelSection] = materialIndex;
				car.paletteSets[0][Car.MODEL_TO_PALETTE[modelSection]] = Png.pngToWdcPalette(materialPaths[materialIndex]);

				int fileNameStart = lastIndexOf(materialPaths[materialIndex], '/');
				fileNameStart = fileNameStart == -1 ? lastIndexOf(materialPaths[materialIndex], '\\') : fileNameStart;
				fileNameStart = fileNameStart == -1 ? 1 : fileNameStart + 1;
				string sourcePath = materialPaths[materialIndex][0..fileNameStart];
				string fileEnd = materialPaths[materialIndex][fileNameStart + 1..$];
				car.paletteSets[1][Car.MODEL_TO_PALETTE[modelSection]] = Png.pngToWdcPalette(sourcePath ~ "1" ~ fileEnd);
				car.paletteSets[2][Car.MODEL_TO_PALETTE[modelSection]] = Png.pngToWdcPalette(sourcePath ~ "2" ~ fileEnd);
			}
		}
		facesToPolygons(modelSection == 26 || modelSection == 27 || modelSection == 28);
		if (modelSection == 26 || modelSection == 27 || modelSection == 28)
		{
			car.models[model].vertices.length -= sectionVertexCount;
		}
		
		car.modelToTextureMap[18] = 14; // static wheel
		int folderEndIndex = lastIndexOf(objFilePath, '/') != -1 ? lastIndexOf(objFilePath, '/') : lastIndexOf(objFilePath, '\\');
		string sourcePath = folderEndIndex == -1 ? "" : objFilePath[0..folderEndIndex + 1];
		car.textures ~= Png.pngToWdcTexture(sourcePath ~ "0_car22_0.png");
		car.paletteSets[0][Car.MODEL_TO_PALETTE[0x1E]] = Png.pngToWdcPalette(sourcePath ~ "0_car22_0.png");
		car.paletteSets[1][Car.MODEL_TO_PALETTE[0x1E]] = Png.pngToWdcPalette(sourcePath ~ "1_car22_0.png");
		car.paletteSets[2][Car.MODEL_TO_PALETTE[0x1E]] = Png.pngToWdcPalette(sourcePath ~ "2_car22_0.png");
		car.textures ~= Png.pngToWdcTexture(sourcePath ~ "0_car23_0.png");
		car.textures ~= Png.pngToWdcTexture(sourcePath ~ "0_car24_0.png");
		car.textures ~= Png.pngToWdcTexture(sourcePath ~ "0_car25_0.png");
		car.modelToTextureMap[0x1E] = 22;
		car.modelToTextureMap[0x1F] = 23;
		car.modelToTextureMap[0x20] = 24;
		car.modelToTextureMap[0x21] = 25;

		car.insertedPaletteIndices = [0,1,2,3,4,5,6,7];
		input.close();
		//removeRepeatedVertices();
		car.generateBinaries();
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