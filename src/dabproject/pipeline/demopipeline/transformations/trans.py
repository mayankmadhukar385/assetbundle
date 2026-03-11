import dlt

@dlt.table
def trans():
    return spark.range(10)