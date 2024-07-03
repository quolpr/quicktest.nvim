import 'package:flutter_test/flutter_test.dart';

void main()
{
	group("Testing", ()
	{
		test("Simple Check", () async
		{
			expect(1 + 1, 2);
		});

		test("Another Check", () async
		{
			expect(1 + 3, 4);
		});
	});

	group("Testification", ()
	{
		test("Simple Check A", () async
		{
			expect(1 + 1, 2);
		});

		test("Another Check B", () async
		{
			expect(1 + 3, 4);
		});
	});
}
