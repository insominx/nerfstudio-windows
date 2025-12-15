import numpy as np

from nerfstudio.scripts.exporter import _c2w_to_w2c_rotation_position


def test_c2w_to_w2c_rotation_position_identity():
    c2w = np.array([[1, 0, 0, 0],
                    [0, 1, 0, 0],
                    [0, 0, 1, 0]], dtype=np.float32)
    r_w2c, t_w2c = _c2w_to_w2c_rotation_position(c2w)
    np.testing.assert_allclose(r_w2c, np.eye(3, dtype=np.float32))
    np.testing.assert_allclose(t_w2c, np.zeros(3, dtype=np.float32))


def test_c2w_to_w2c_rotation_position_translation_only():
    # Camera at world position (1,2,3) looking with identity rotation.
    c2w = np.array([[1, 0, 0, 1],
                    [0, 1, 0, 2],
                    [0, 0, 1, 3]], dtype=np.float32)
    r_w2c, t_w2c = _c2w_to_w2c_rotation_position(c2w)
    np.testing.assert_allclose(r_w2c, np.eye(3, dtype=np.float32))
    np.testing.assert_allclose(t_w2c, np.array([-1, -2, -3], dtype=np.float32))

