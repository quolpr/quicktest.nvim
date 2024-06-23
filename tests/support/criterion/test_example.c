#include <criterion/criterion.h>
#include <criterion/new/assert.h>
#include <criterion/parameterized.h>
#include <criterion/logging.h>

struct test_param
{
    int a;
    int b;
    int sum;
};

ParameterizedTestParameters(ts_example, test_sum_parameterized)
{
    static struct test_param test_parameters[] = {
        {1, 2, 3},
        {4, 5, 9},
    };

    return cr_make_param_array(struct test_param, test_parameters, sizeof(test_parameters) / sizeof(test_parameters[0]));
}

ParameterizedTest(struct test_param* param, ts_example, test_sum_parameterized, .description = "Simple parameterized test")
{
    cr_assert(eq(int, param->a + param->b, param->sum));
}

Test(ts_example, test_sum_basic, .description = "Simple test")
{
    cr_assert(eq(int, 1 + 2, 3));
}

