from ray import serve

@serve.deployment
class Test:
    pass

print("Test class:", type(Test))
print("Has deploy method:", hasattr(Test, 'deploy'))
print("Options returns:", type(Test.options(name="test")))
print("Options has deploy:", hasattr(Test.options(name="test"), 'deploy'))

